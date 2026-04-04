import Foundation

struct PaintPaletteResult {
    let selectedTubes: [PigmentData]
    let recipes: [PigmentRecipe]
    let pixelLabels: [Int32]
    let clusterPixelCounts: [Int]
    let clippedRecipeIndices: [Int]
}

enum PaintPaletteBuilder {
    
    enum BuilderError: Error {
        case missingData
        case refinementFailed
    }

    private static let adaptivePruneErrorThreshold: Float = 0.005 // Per-pixel weighted error increase threshold

    static func build(
        colorRegions: ColorRegionsProcessor.Result,
        config: ColorConfig,
        database: SpectralDatabase,
        pigments: [PigmentData],
        onProgress: ((Double) -> Void)? = nil
    ) throws -> PaintPaletteResult {
        
        guard !colorRegions.quantizedCentroids.isEmpty else {
            throw BuilderError.missingData
        }
        
        // Grab the shared precomputed table once (nil → falls back to runtime build).
        let lookupTable = SpectralDataStore.sharedLookupTable

        let t0 = CFAbsoluteTimeGetCurrent()

        // Stage 2 - Preliminary Decomposition
        _ = PigmentDecomposer.decompose(
            targetColors: colorRegions.quantizedCentroids,
            pigments: pigments,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration,
            lookupTable: lookupTable
        )
        
        let t1 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 2 (Prelim Decomp) took \(String(format: "%.1f", (t1 - t0) * 1000)) ms")
        onProgress?(0.35)
        
        // Stage 3 - skipped: user-selected pigments are used directly as selectedTubes.
        let selectedTubes = pigments
        
        let t2 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 3 (Tube Selection) skipped – using \(selectedTubes.count) user-selected tubes")
        onProgress?(0.50)
        
        // Stage 4A - Constrained Decomposition
        let constrainedRecipes = PigmentDecomposer.decompose(
            targetColors: colorRegions.quantizedCentroids,
            pigments: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration,
            lookupTable: lookupTable
        )

        guard !constrainedRecipes.isEmpty else {
            throw BuilderError.missingData
        }

        let t3 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4A (Constrained Decomp) took \(String(format: "%.1f", (t3 - t2) * 1000)) ms")
        onProgress?(0.60)

        // Stage 4B - Snap/Reassign Loop
        let (workingRecipes, snappedCentroidToRecipe, snappedCounts) = snapAndReassign(
            recipes: constrainedRecipes,
            colorRegions: colorRegions,
            selectedTubes: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration,
            lookupTable: lookupTable
        )

        let t3b = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4B (Snap/Reassign) took \(String(format: "%.1f", (t3b - t3) * 1000)) ms")
        onProgress?(0.75)

        // Stage 5 - Merge, Prune, and Finalize
        // All intermediate work operates on centroid-level labels (size K ≈ 50).
        // A single O(pixels) projection is deferred to the very end.

        let (mergedRecipes, mergeMap) = PigmentDecomposer.mergeRecipes(
            recipes: workingRecipes,
            pixelCounts: snappedCounts
        )

        let mergeMapI32 = mergeMap.map { Int32($0) }
        var qCentroidLabels = snappedCentroidToRecipe.map { mergeMapI32[Int($0)] }
        var finalRecipes = mergedRecipes

        // O(K) counts via quantized centroids.
        var finalCounts = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
            quantizedCentroids: colorRegions.quantizedCentroids,
            quantizedPixelCounts: colorRegions.clusterPixelCounts,
            centroidToRecipe: qCentroidLabels,
            recipeCount: finalRecipes.count
        ).counts

        // Stage 5A - Adaptive shade count
        let anchors5A: Set<Int> = {
            let threshold = max(1, colorRegions.clusterPixelCounts.reduce(0, +) / 100)
            var minL: Float = .greatestFiniteMagnitude
            var maxL: Float = -.greatestFiniteMagnitude
            var darkest: Int? = nil
            var lightest: Int? = nil
            for i in 0..<finalRecipes.count where finalCounts[i] > threshold {
                let L = finalRecipes[i].predictedColor.L
                if L < minL { minL = L; darkest = i }
                if L > maxL { maxL = L; lightest = i }
            }
            return Set([darkest, lightest].compactMap { $0 })
        }()

        finalRecipes = adaptivePrune(
            recipes: finalRecipes,
            counts: finalCounts,
            labels: &qCentroidLabels,
            anchors: anchors5A,
            minShades: config.numShades
        )

        // Recompute counts after prune (O(K)).
        finalCounts = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
            quantizedCentroids: colorRegions.quantizedCentroids,
            quantizedPixelCounts: colorRegions.clusterPixelCounts,
            centroidToRecipe: qCentroidLabels,
            recipeCount: finalRecipes.count
        ).counts

        // Prune down to numShades.
        if finalRecipes.count > config.numShades && config.numShades > 1 {
            finalRecipes = pruneToMaxShades(
                recipes: finalRecipes,
                counts: finalCounts,
                labels: &qCentroidLabels,
                maxShades: config.numShades
            )
            // Recompute counts after prune.
            finalCounts = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
                quantizedCentroids: colorRegions.quantizedCentroids,
                quantizedPixelCounts: colorRegions.clusterPixelCounts,
                centroidToRecipe: qCentroidLabels,
                recipeCount: finalRecipes.count
            ).counts
        }

        // Compact: remove recipes with no pixels. O(K).
        let validIndices = (0..<finalRecipes.count).filter { finalCounts[$0] > 0 }
        let prunedRecipes = validIndices.map { finalRecipes[$0] }
        var newIndexMap = [Int32](repeating: 0, count: finalRecipes.count)
        for (newIdx, oldIdx) in validIndices.enumerated() {
            newIndexMap[oldIdx] = Int32(newIdx)
        }
        qCentroidLabels = qCentroidLabels.map { newIndexMap[Int($0)] }

        finalCounts = [Int](repeating: 0, count: prunedRecipes.count)
        for qi in 0..<qCentroidLabels.count {
            let ri = Int(qCentroidLabels[qi])
            if ri >= 0, ri < finalCounts.count { finalCounts[ri] += colorRegions.clusterPixelCounts[qi] }
        }

        // Stage 5B - Final Constrained Refit (O(K) centroid computation, no full pixel scan).
        let (refitCentroids, refitCounts) = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
            quantizedCentroids: colorRegions.quantizedCentroids,
            quantizedPixelCounts: colorRegions.clusterPixelCounts,
            centroidToRecipe: qCentroidLabels,
            recipeCount: prunedRecipes.count
        )

        var refitRecipes = prunedRecipes
        for i in 0..<refitCentroids.count where refitCounts[i] > 0 {
            let reDecomposed = PigmentDecomposer.decompose(
                targetColors: [refitCentroids[i]],
                pigments: selectedTubes,
                database: database,
                maxPigments: config.maxPigmentsPerMix,
                minConcentration: config.minConcentration,
                concurrent: false,
                lookupTable: lookupTable
            )
            if let recipe = reDecomposed.first {
                refitRecipes[i] = recipe
            }
        }

        // Final pixel assignment: O(K × r) centroid assign + single O(pixels) projection.
        var finalQToRecipe = ColorRegionsProcessor.assignQuantizedToRecipes(
            quantizedCentroids: colorRegions.quantizedCentroids,
            recipeCentroids: refitRecipes.map { $0.predictedColor },
            lWeight: 0.3
        )

        // Stage 5C - Dedup: merge recipes with identical quantized signatures.
        (refitRecipes, finalQToRecipe) = deduplicateRecipes(
            recipes: refitRecipes,
            centroidToRecipe: finalQToRecipe
        )

        let finalPixelLabels = ColorRegionsProcessor.projectQuantizedLabels(
            pixelQuantizedLabels: colorRegions.pixelLabels,
            centroidToRecipe: finalQToRecipe
        )

        finalCounts = [Int](repeating: 0, count: refitRecipes.count)
        for qi in 0..<finalQToRecipe.count {
            let ri = Int(finalQToRecipe[qi])
            if ri >= 0, ri < finalCounts.count { finalCounts[ri] += colorRegions.clusterPixelCounts[qi] }
        }

        var clippedIndices = [Int]()
        for (i, recipe) in refitRecipes.enumerated() {
            if recipe.deltaE > 0.05 {
                clippedIndices.append(i)
            }
        }

        let t4 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 5 (Merge, Prune & Refit) took \(String(format: "%.1f", (t4 - t3b) * 1000)) ms")
        print("[PaintPaletteBuilder] Total execution took \(String(format: "%.1f", (t4 - t0) * 1000)) ms")
        onProgress?(0.95)

        return PaintPaletteResult(
            selectedTubes: selectedTubes,
            recipes: refitRecipes,
            pixelLabels: finalPixelLabels,
            clusterPixelCounts: finalCounts,
            clippedRecipeIndices: clippedIndices
        )
    }
    
    private static func snapAndReassign(
        recipes: [PigmentRecipe],
        colorRegions: ColorRegionsProcessor.Result,
        selectedTubes: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int,
        minConcentration: Float,
        iterations: Int = 2,
        lookupTable: PigmentLookupTable? = nil
    ) -> (recipes: [PigmentRecipe], centroidToRecipe: [Int32], counts: [Int]) {
        guard !recipes.isEmpty else {
            return ([], [Int32](repeating: 0, count: colorRegions.quantizedCentroids.count), [])
        }

        let qCentroids   = colorRegions.quantizedCentroids
        let qCounts      = colorRegions.clusterPixelCounts

        var currentRecipes   = recipes
        var currentCentroids = recipes.map { $0.predictedColor }

        for _ in 0..<iterations {
            // O(K × recipeCount): assign each quantized centroid to nearest recipe.
            let centroidToRecipe = ColorRegionsProcessor.assignQuantizedToRecipes(
                quantizedCentroids: qCentroids,
                recipeCentroids: currentCentroids,
                lWeight: 0.3
            )

            // O(K): compute new recipe centroids weighted by pixel counts.
            let (newCentroids, newCounts) = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
                quantizedCentroids: qCentroids,
                quantizedPixelCounts: qCounts,
                centroidToRecipe: centroidToRecipe,
                recipeCount: currentCentroids.count
            )

            // Re-decompose only centroids that moved significantly (or became empty).
            var updatedRecipes = currentRecipes
            for i in 0..<newCentroids.count {
                guard newCounts[i] > 0 else { continue }
                let moved = oklabDistance(newCentroids[i], currentCentroids[i])
                if moved > 0.0001 {
                    let reDecomposed = PigmentDecomposer.decompose(
                        targetColors: [newCentroids[i]],
                        pigments: selectedTubes,
                        database: database,
                        maxPigments: maxPigments,
                        minConcentration: minConcentration,
                        concurrent: false,
                        lookupTable: lookupTable
                    )
                    if let recipe = reDecomposed.first {
                        updatedRecipes[i] = recipe
                    }
                }
            }

            currentRecipes   = updatedRecipes
            currentCentroids = currentRecipes.map { $0.predictedColor }
        }

        // Final assignment: O(K × r) centroid-level mapping — no per-pixel work.
        let finalCentroidToRecipe = ColorRegionsProcessor.assignQuantizedToRecipes(
            quantizedCentroids: qCentroids,
            recipeCentroids: currentCentroids,
            lWeight: 0.3
        )
        let (_, finalCounts) = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
            quantizedCentroids: qCentroids,
            quantizedPixelCounts: qCounts,
            centroidToRecipe: finalCentroidToRecipe,
            recipeCount: currentCentroids.count
        )

        return (currentRecipes, finalCentroidToRecipe, finalCounts)
    }

    /// Merge recipes that have identical quantized pigment signatures.
    /// Returns compacted recipes and remapped centroid-to-recipe labels.
    private static func deduplicateRecipes(
        recipes: [PigmentRecipe],
        centroidToRecipe: [Int32]
    ) -> (recipes: [PigmentRecipe], centroidToRecipe: [Int32]) {
        // Build a signature for each recipe: sorted (pigmentId, quantizedConc) pairs.
        func signature(of recipe: PigmentRecipe) -> String {
            recipe.components
                .map { "\($0.pigmentId):\(Int(($0.concentration * 8).rounded()))" }
                .sorted()
                .joined(separator: "|")
        }

        var signatureToNew = [String: Int]()
        var dedupedRecipes = [PigmentRecipe]()
        var oldToNew = [Int32](repeating: 0, count: recipes.count)

        for (i, recipe) in recipes.enumerated() {
            let sig = signature(of: recipe)
            if let existing = signatureToNew[sig] {
                oldToNew[i] = Int32(existing)
            } else {
                let newIdx = dedupedRecipes.count
                signatureToNew[sig] = newIdx
                dedupedRecipes.append(recipe)
                oldToNew[i] = Int32(newIdx)
            }
        }

        guard dedupedRecipes.count < recipes.count else {
            return (recipes, centroidToRecipe)
        }

        let remapped = centroidToRecipe.map { oldToNew[Int($0)] }
        return (dedupedRecipes, remapped)
    }

    private static func adaptivePrune(
        recipes: [PigmentRecipe],
        counts: [Int],
        labels: inout [Int32],
        anchors: Set<Int>,
        minShades: Int
    ) -> [PigmentRecipe] {
        let totalPixels = max(1, counts.reduce(0, +))
        var survivors = Array(0..<recipes.count)
        let targetMax = max(2, minShades)

        while survivors.count > targetMax {
            // Find weakest non-anchor by pixel count
            var weakestIdx = -1
            var weakestCount = Int.max

            for s in survivors where !anchors.contains(s) {
                if counts[s] < weakestCount {
                    weakestCount = counts[s]
                    weakestIdx = s
                }
            }

            guard weakestIdx >= 0 else { break }

            // Find nearest survivor to the candidate for removal
            let removedColor = recipes[weakestIdx].predictedColor
            var nearestDist: Float = .greatestFiniteMagnitude
            for s in survivors where s != weakestIdx {
                let d = oklabDistance(removedColor, recipes[s].predictedColor)
                if d < nearestDist { nearestDist = d }
            }

            // Estimate error increase from removing this shade
            // Pixels currently assigned to it would go to the nearest survivor
            let errorIncrease = Float(weakestCount) * sqrtf(nearestDist)
            let perPixelIncrease = errorIncrease / Float(totalPixels)

            if perPixelIncrease >= adaptivePruneErrorThreshold { break }

            survivors.removeAll { $0 == weakestIdx }
        }

        // Only reassign labels if we actually removed something
        guard survivors.count < recipes.count else { return recipes }

        // Build a compacted index: original recipe index → contiguous survivor index
        var oldToNew = [Int: Int32]()
        for (newIdx, oldIdx) in survivors.enumerated() {
            oldToNew[oldIdx] = Int32(newIdx)
        }

        // Map eliminated recipe indices to their nearest survivor's new index
        var indexMap = [Int32](repeating: 0, count: recipes.count)
        for i in 0..<recipes.count {
            if let newIdx = oldToNew[i] {
                indexMap[i] = newIdx
            } else {
                let droppedColor = recipes[i].predictedColor
                var bestDist = Float.greatestFiniteMagnitude
                var bestNewIdx: Int32 = 0
                for (origIdx, newIdx) in oldToNew {
                    let d = oklabDistance(droppedColor, recipes[origIdx].predictedColor)
                    if d < bestDist {
                        bestDist = d
                        bestNewIdx = newIdx
                    }
                }
                indexMap[i] = bestNewIdx
            }
        }

        labels = labels.map { indexMap[Int($0)] }
        return survivors.map { recipes[$0] }
    }

    private static func pruneToMaxShades(
        recipes: [PigmentRecipe],
        counts: [Int],
        labels: inout [Int32],
        maxShades: Int
    ) -> [PigmentRecipe] {
        var survivors = Array(0..<recipes.count)
        guard !survivors.isEmpty else { return [] }
        
        // Identify anchors
        let nonTrivialThreshold = max(1, counts.reduce(0, +) / 100)
        var darkest: Int? = nil
        var lightest: Int? = nil
        var neutral: Int? = nil
        var minL: Float = .greatestFiniteMagnitude
        var maxL: Float = -.greatestFiniteMagnitude
        var minChroma: Float = .greatestFiniteMagnitude
        
        for i in 0..<recipes.count where counts[i] > nonTrivialThreshold {
            let c = recipes[i].predictedColor
            if c.L < minL {
                minL = c.L
                darkest = i
            }
            if c.L > maxL {
                maxL = c.L
                lightest = i
            }
            let chroma = sqrtf(c.a * c.a + c.b * c.b)
            if chroma < minChroma && chroma < 0.05 { // neutral threshold
                minChroma = chroma
                neutral = i
            }
        }
        
        let anchors = Set([darkest, lightest, neutral].compactMap { $0 })
        
        while survivors.count > maxShades {
            // Find weakest non-anchor
            var weakestVal = Int.max
            var weakestIdx = -1
            
            for s in survivors where !anchors.contains(s) {
                if counts[s] < weakestVal {
                    weakestVal = counts[s]
                    weakestIdx = s
                }
            }
            
            guard weakestIdx >= 0 else { break }
            survivors.removeAll(where: { $0 == weakestIdx })
        }
        
        // Reassign eliminated labels strictly logically to preserve Palette Spread spatial geometry
        var indexMap = [Int32](repeating: 0, count: recipes.count)
        for i in 0..<recipes.count {
            if survivors.contains(i) {
                indexMap[i] = Int32(i)
            } else {
                let droppedColor = recipes[i].predictedColor
                var bestDist = Float.greatestFiniteMagnitude
                var bestSurv = survivors[0]
                for s in survivors {
                    let d = oklabDistance(droppedColor, recipes[s].predictedColor)
                    if d < bestDist {
                        bestDist = d
                        bestSurv = s
                    }
                }
                indexMap[i] = Int32(bestSurv)
            }
        }
        
        labels = labels.map { indexMap[Int($0)] }
        
        return recipes
    }
}
