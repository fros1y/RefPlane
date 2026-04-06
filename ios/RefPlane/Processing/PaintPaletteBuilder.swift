import Foundation
import os

struct PaintPaletteResult {
    let selectedTubes: [PigmentData]
    let recipes: [PigmentRecipe]
    let pixelLabels: [Int32]
    let clusterPixelCounts: [Int]
    let clippedRecipeIndices: [Int]
}

enum PaintPaletteBuilder {

    private static let signpostLog = AppInstrumentation.signpostLog(category: "Processing.PaintPalette")
    
    enum BuilderError: Error {
        case missingData
        case refinementFailed
    }

    private static let adaptivePruneErrorThreshold: Float = 0.005 // Per-pixel weighted error increase threshold
    private static let chromaticAnchorThreshold: Float = 0.04
    private static let hueAnchorSeparation: Float = 0.55

    static func build(
        colorRegions: ColorRegionsProcessor.Result,
        config: ColorConfig,
        database: SpectralDatabase,
        pigments: [PigmentData],
        onProgress: ((Double) -> Void)? = nil
    ) throws -> PaintPaletteResult {
        try AppInstrumentation.measure("BuildPaintPalette", log: signpostLog) {
            guard !colorRegions.quantizedCentroids.isEmpty else {
                throw BuilderError.missingData
            }

            let lookupTable = SpectralDataStore.sharedLookupTable
            let assignmentLWeight = centroidAssignmentLWeight(
                for: colorRegions.quantizedCentroids
            )

            _ = AppInstrumentation.measure("PreliminaryDecomposition", log: signpostLog) {
                PigmentDecomposer.decompose(
                    targetColors: colorRegions.quantizedCentroids,
                    pigments: pigments,
                    database: database,
                    maxPigments: config.maxPigmentsPerMix,
                    minConcentration: config.minConcentration,
                    concurrent: false,
                    lookupTable: lookupTable
                )
            }
            onProgress?(0.35)

            let selectedTubes = AppInstrumentation.measure("SelectUserTubes", log: signpostLog) {
                pigments
            }
            onProgress?(0.50)

            let constrainedRecipes = AppInstrumentation.measure("ConstrainedDecomposition", log: signpostLog) {
                PigmentDecomposer.decompose(
                    targetColors: colorRegions.quantizedCentroids,
                    pigments: selectedTubes,
                    database: database,
                    maxPigments: config.maxPigmentsPerMix,
                    minConcentration: config.minConcentration,
                    concurrent: false,
                    lookupTable: lookupTable
                )
            }

            guard !constrainedRecipes.isEmpty else {
                throw BuilderError.missingData
            }
            onProgress?(0.60)

            let (workingRecipes, snappedCentroidToRecipe, snappedCounts) = AppInstrumentation.measure("SnapAndReassign", log: signpostLog) {
                snapAndReassign(
                    recipes: constrainedRecipes,
                    colorRegions: colorRegions,
                    selectedTubes: selectedTubes,
                    database: database,
                    maxPigments: config.maxPigmentsPerMix,
                    minConcentration: config.minConcentration,
                    assignmentLWeight: assignmentLWeight,
                    lookupTable: lookupTable
                )
            }
            onProgress?(0.75)

            let (refitRecipes, finalPixelLabels, finalCounts, clippedIndices) = AppInstrumentation.measure("MergePruneRefit", log: signpostLog) {
                let (mergedRecipes, mergeMap) = PigmentDecomposer.mergeRecipes(
                    recipes: workingRecipes,
                    pixelCounts: snappedCounts
                )

                let mergeMapI32 = mergeMap.map { Int32($0) }
                var qCentroidLabels = snappedCentroidToRecipe.map { mergeMapI32[Int($0)] }
                var finalRecipes = mergedRecipes

                var finalCounts = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
                    quantizedCentroids: colorRegions.quantizedCentroids,
                    quantizedPixelCounts: colorRegions.clusterPixelCounts,
                    centroidToRecipe: qCentroidLabels,
                    recipeCount: finalRecipes.count
                ).counts
                var finalImportances = recipeImportances(
                    quantizedPixelCounts: colorRegions.clusterPixelCounts,
                    quantizedSalience: colorRegions.clusterSalience,
                    centroidToRecipe: qCentroidLabels,
                    recipeCount: finalRecipes.count
                )

                let anchors5A = makePruningAnchors(
                    recipes: finalRecipes,
                    counts: finalCounts,
                    importances: finalImportances,
                    maxAnchors: max(2, config.numShades)
                )

                finalRecipes = adaptivePrune(
                    recipes: finalRecipes,
                    counts: finalCounts,
                    importances: finalImportances,
                    labels: &qCentroidLabels,
                    anchors: anchors5A,
                    minShades: config.numShades
                )

                finalCounts = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
                    quantizedCentroids: colorRegions.quantizedCentroids,
                    quantizedPixelCounts: colorRegions.clusterPixelCounts,
                    centroidToRecipe: qCentroidLabels,
                    recipeCount: finalRecipes.count
                ).counts
                finalImportances = recipeImportances(
                    quantizedPixelCounts: colorRegions.clusterPixelCounts,
                    quantizedSalience: colorRegions.clusterSalience,
                    centroidToRecipe: qCentroidLabels,
                    recipeCount: finalRecipes.count
                )

                if finalRecipes.count > config.numShades && config.numShades > 1 {
                    finalRecipes = pruneToMaxShades(
                        recipes: finalRecipes,
                        counts: finalCounts,
                        importances: finalImportances,
                        labels: &qCentroidLabels,
                        maxShades: config.numShades
                    )
                    finalCounts = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
                        quantizedCentroids: colorRegions.quantizedCentroids,
                        quantizedPixelCounts: colorRegions.clusterPixelCounts,
                        centroidToRecipe: qCentroidLabels,
                        recipeCount: finalRecipes.count
                    ).counts
                    finalImportances = recipeImportances(
                        quantizedPixelCounts: colorRegions.clusterPixelCounts,
                        quantizedSalience: colorRegions.clusterSalience,
                        centroidToRecipe: qCentroidLabels,
                        recipeCount: finalRecipes.count
                    )
                }

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

                var finalQToRecipe = ColorRegionsProcessor.assignQuantizedToRecipes(
                    quantizedCentroids: colorRegions.quantizedCentroids,
                    recipeCentroids: refitRecipes.map { $0.predictedColor },
                    lWeight: assignmentLWeight
                )

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

                return (refitRecipes, finalPixelLabels, finalCounts, clippedIndices)
            }
            onProgress?(0.95)

            return PaintPaletteResult(
                selectedTubes: selectedTubes,
                recipes: refitRecipes,
                pixelLabels: finalPixelLabels,
                clusterPixelCounts: finalCounts,
                clippedRecipeIndices: clippedIndices
            )
        }
    }
    
    private static func snapAndReassign(
        recipes: [PigmentRecipe],
        colorRegions: ColorRegionsProcessor.Result,
        selectedTubes: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int,
        minConcentration: Float,
        assignmentLWeight: Float,
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
                lWeight: assignmentLWeight
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
            lWeight: assignmentLWeight
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
        importances: [Float],
        labels: inout [Int32],
        anchors: Set<Int>,
        minShades: Int
    ) -> [PigmentRecipe] {
        let totalImportance = max(1, importances.reduce(0, +))
        var survivors = Array(0..<recipes.count)
        let targetMax = max(2, minShades)

        while survivors.count > targetMax {
            // Find weakest non-anchor by perceptual importance
            var weakestIdx = -1
            var weakestImportance = Float.greatestFiniteMagnitude

            for s in survivors where !anchors.contains(s) {
                let importance = s < importances.count ? importances[s] : Float(counts[s])
                if importance < weakestImportance {
                    weakestImportance = importance
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
            let errorIncrease = weakestImportance * sqrtf(nearestDist)
            let perPixelIncrease = errorIncrease / totalImportance

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
        importances: [Float],
        labels: inout [Int32],
        maxShades: Int
    ) -> [PigmentRecipe] {
        var survivors = Array(0..<recipes.count)
        guard !survivors.isEmpty else { return [] }
        let anchors = makePruningAnchors(
            recipes: recipes,
            counts: counts,
            importances: importances,
            maxAnchors: maxShades
        )
        
        while survivors.count > maxShades {
            // Find weakest non-anchor by perceptual importance
            var weakestVal = Float.greatestFiniteMagnitude
            var weakestIdx = -1
            
            for s in survivors where !anchors.contains(s) {
                let importance = s < importances.count ? importances[s] : Float(counts[s])
                if importance < weakestVal {
                    weakestVal = importance
                    weakestIdx = s
                }
            }
            
            guard weakestIdx >= 0 else { break }
            survivors.removeAll(where: { $0 == weakestIdx })
        }
        
        // Reassign eliminated labels to the nearest surviving recipe and compact
        // survivor indices so labels and recipe arrays stay aligned.
        var oldToNew = [Int: Int32]()
        for (newIndex, oldIndex) in survivors.enumerated() {
            oldToNew[oldIndex] = Int32(newIndex)
        }
        var indexMap = [Int32](repeating: 0, count: recipes.count)
        for i in 0..<recipes.count {
            if let newIndex = oldToNew[i] {
                indexMap[i] = newIndex
            } else {
                let droppedColor = recipes[i].predictedColor
                var bestDist = Float.greatestFiniteMagnitude
                var bestSurvivor = survivors[0]
                for survivor in survivors {
                    let d = oklabDistance(
                        droppedColor,
                        recipes[survivor].predictedColor
                    )
                    if d < bestDist {
                        bestDist = d
                        bestSurvivor = survivor
                    }
                }
                indexMap[i] = oldToNew[bestSurvivor] ?? 0
            }
        }
        
        labels = labels.map { indexMap[Int($0)] }

        return survivors.map { recipes[$0] }
    }

    private static func makePruningAnchors(
        recipes: [PigmentRecipe],
        counts: [Int],
        importances: [Float],
        maxAnchors: Int
    ) -> Set<Int> {
        let totalCount = max(1, counts.reduce(0, +))
        let valueAnchorThreshold = max(1, totalCount / 100)
        let chromaticAnchorThresholdCount = max(1, totalCount / 500)
        let anchorLimit = min(max(recipes.count, 0), max(2, maxAnchors))

        var darkest: Int?
        var lightest: Int?
        var neutral: Int?
        var minL = Float.greatestFiniteMagnitude
        var maxL = -Float.greatestFiniteMagnitude
        var minChroma = Float.greatestFiniteMagnitude

        for i in 0..<recipes.count where i < counts.count && counts[i] > valueAnchorThreshold {
            let color = recipes[i].predictedColor
            if color.L < minL {
                minL = color.L
                darkest = i
            }
            if color.L > maxL {
                maxL = color.L
                lightest = i
            }

            let chroma = sqrtf((color.a * color.a) + (color.b * color.b))
            if chroma < minChroma && chroma < chromaticAnchorThreshold {
                minChroma = chroma
                neutral = i
            }
        }

        var anchors = Set<Int>()
        for index in [darkest, lightest, neutral].compactMap({ $0 }) where anchors.count < anchorLimit {
            anchors.insert(index)
        }

        guard anchors.count < anchorLimit else { return anchors }

        struct HueCandidate {
            let index: Int
            let hue: Float
            let chroma: Float
            let score: Float
        }

        let chromaticCandidates = recipes.indices.compactMap { index -> HueCandidate? in
            guard index < counts.count,
                  counts[index] > chromaticAnchorThresholdCount,
                  !anchors.contains(index) else {
                return nil
            }

            let color = recipes[index].predictedColor
            let chroma = sqrtf((color.a * color.a) + (color.b * color.b))
            guard chroma >= chromaticAnchorThreshold else { return nil }

            let importance = index < importances.count
                ? max(0, importances[index])
                : Float(counts[index])
            let chromaBoost = 1 + min(chroma / 0.2, 1)
            return HueCandidate(
                index: index,
                hue: atan2f(color.b, color.a),
                chroma: chroma,
                score: importance * chromaBoost
            )
        }

        for candidate in [
            chromaticCandidates.min(by: { lhs, rhs in
                let lhsA = recipes[lhs.index].predictedColor.a
                let rhsA = recipes[rhs.index].predictedColor.a
                if lhsA != rhsA { return lhsA < rhsA }
                return lhs.score < rhs.score
            }),
            chromaticCandidates.max(by: { lhs, rhs in
                let lhsA = recipes[lhs.index].predictedColor.a
                let rhsA = recipes[rhs.index].predictedColor.a
                if lhsA != rhsA { return lhsA < rhsA }
                return lhs.score < rhs.score
            }),
            chromaticCandidates.min(by: { lhs, rhs in
                let lhsB = recipes[lhs.index].predictedColor.b
                let rhsB = recipes[rhs.index].predictedColor.b
                if lhsB != rhsB { return lhsB < rhsB }
                return lhs.score < rhs.score
            }),
            chromaticCandidates.max(by: { lhs, rhs in
                let lhsB = recipes[lhs.index].predictedColor.b
                let rhsB = recipes[rhs.index].predictedColor.b
                if lhsB != rhsB { return lhsB < rhsB }
                return lhs.score < rhs.score
            })
        ].compactMap({ $0 }) where anchors.count < anchorLimit {
            anchors.insert(candidate.index)
        }

        guard anchors.count < anchorLimit else { return anchors }

        let hueCandidates = chromaticCandidates
            .filter { !anchors.contains($0.index) }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.chroma != $1.chroma { return $0.chroma > $1.chroma }
            return $0.index < $1.index
        }

        var anchoredHues = anchors.compactMap { index -> Float? in
            guard recipes.indices.contains(index) else { return nil }
            let color = recipes[index].predictedColor
            let chroma = sqrtf((color.a * color.a) + (color.b * color.b))
            guard chroma >= chromaticAnchorThreshold else { return nil }
            return atan2f(color.b, color.a)
        }

        for candidate in hueCandidates {
            guard anchors.count < anchorLimit else { break }
            let isHueSeparated = anchoredHues.allSatisfy { hue in
                circularHueDistance(candidate.hue, hue) >= hueAnchorSeparation
            }
            guard isHueSeparated else { continue }

            anchors.insert(candidate.index)
            anchoredHues.append(candidate.hue)
        }

        return anchors
    }

    private static func circularHueDistance(_ lhs: Float, _ rhs: Float) -> Float {
        let raw = abs(lhs - rhs)
        return min(raw, (2 * Float.pi) - raw)
    }

    private static func recipeImportances(
        quantizedPixelCounts: [Int],
        quantizedSalience: [Float],
        centroidToRecipe: [Int32],
        recipeCount: Int
    ) -> [Float] {
        guard recipeCount > 0 else { return [] }

        var importances = [Float](repeating: 0, count: recipeCount)
        let centroidCount = min(quantizedPixelCounts.count, centroidToRecipe.count)

        for centroidIndex in 0..<centroidCount {
            let recipeIndex = Int(centroidToRecipe[centroidIndex])
            guard recipeIndex >= 0, recipeIndex < recipeCount else { continue }

            let salience = centroidIndex < quantizedSalience.count
                ? max(0.1, quantizedSalience[centroidIndex])
                : 1
            importances[recipeIndex] += Float(quantizedPixelCounts[centroidIndex]) * salience
        }

        return importances
    }

    private static func centroidAssignmentLWeight(
        for quantizedCentroids: [OklabColor]
    ) -> Float {
        let maxChroma = quantizedCentroids.reduce(0) { currentMax, color in
            max(currentMax, sqrtf((color.a * color.a) + (color.b * color.b)))
        }

        return maxChroma < 0.01 ? 1.0 : 0.3
    }
}
