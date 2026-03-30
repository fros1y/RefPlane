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

    static func build(
        colorRegions: ColorRegionsProcessor.Result,
        config: ColorConfig,
        database: SpectralDatabase,
        pigments: [PigmentData],
        onProgress: ((Double) -> Void)? = nil
    ) throws -> PaintPaletteResult {
        
        let t0 = CFAbsoluteTimeGetCurrent()
        
        guard !colorRegions.quantizedCentroids.isEmpty else {
            throw BuilderError.missingData
        }
        
        // Stage 2 - Preliminary Decomposition
        let prelimRecipes = PigmentDecomposer.decompose(
            targetColors: colorRegions.quantizedCentroids,
            pigments: pigments,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )
        
        let t1 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 2 (Prelim Decomp) took \(String(format: "%.1f", (t1 - t0) * 1000)) ms")
        onProgress?(0.35)
        
        // Stage 3 - Tube Selection
        let seedTubes = PigmentDecomposer.selectTubes(
            preliminaryRecipes: prelimRecipes,
            pixelCounts: colorRegions.clusterPixelCounts,
            clusterSalience: colorRegions.clusterSalience,
            maxTubes: config.numTubes,
            allPigments: pigments,
            database: database
        )
        
        let selectedTubes = PigmentDecomposer.improveTubeSet(
            seedTubes: seedTubes,
            targetColors: colorRegions.quantizedCentroids,
            clusterWeights: colorRegions.clusterSalience.enumerated().map { i, salience in
                Float(colorRegions.clusterPixelCounts[i]) * salience
            },
            allPigments: pigments,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )
        
        guard !selectedTubes.isEmpty else {
            throw BuilderError.refinementFailed
        }
        
        let t2 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 3 (Tube Selection) took \(String(format: "%.1f", (t2 - t1) * 1000)) ms")
        onProgress?(0.50)
        
        // Stage 4A - Constrained Decomposition
        let constrainedRecipes = PigmentDecomposer.decompose(
            targetColors: colorRegions.quantizedCentroids,
            pigments: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )

        let t3 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4A (Constrained Decomp) took \(String(format: "%.1f", (t3 - t2) * 1000)) ms")
        onProgress?(0.60)

        // Stage 4B - Snap/Reassign Loop
        let (workingRecipes, snappedLabels, snappedCounts) = snapAndReassign(
            recipes: constrainedRecipes,
            pixelLab: colorRegions.pixelLab,
            selectedTubes: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )

        let t3b = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4B (Snap/Reassign) took \(String(format: "%.1f", (t3b - t3) * 1000)) ms")
        onProgress?(0.75)

        // Stage 5 - Merge, Prune, and Finalize
        let (mergedRecipes, mergeMap) = PigmentDecomposer.mergeRecipes(
            recipes: workingRecipes,
            pixelCounts: snappedCounts
        )

        var workingLabels = snappedLabels.map { Int32(mergeMap[Int($0)]) }
        
        var finalCounts = [Int](repeating: 0, count: mergedRecipes.count)
        for label in workingLabels {
            finalCounts[Int(label)] += 1
        }
        
        var finalRecipes = mergedRecipes
        
        // Prune down to numShades safely using index mapping to protect cluster geometry
        if finalRecipes.count > config.numShades && config.numShades > 1 {
            finalRecipes = pruneToMaxShades(
                recipes: finalRecipes,
                counts: finalCounts,
                labels: &workingLabels,
                maxShades: config.numShades
            )
        }
        
        // Clean up empty indices
        let validIndices = (0..<finalRecipes.count).filter { i in workingLabels.contains(Int32(i)) }
        let prunedRecipes = validIndices.map { finalRecipes[$0] }
        let newLabelMap = Dictionary(uniqueKeysWithValues: validIndices.enumerated().map { ($1, Int32($0)) })
        workingLabels = workingLabels.map { newLabelMap[Int($0)] ?? 0 }
        
        finalCounts = [Int](repeating: 0, count: prunedRecipes.count)
        for label in workingLabels {
            finalCounts[Int(label)] += 1
        }
        
        var clippedIndices = [Int]()
        for (i, recipe) in prunedRecipes.enumerated() {
            if recipe.deltaE > 0.05 { // Materially high delta E
                clippedIndices.append(i)
            }
        }
        
        let t4 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 5 (Merge & Prune) took \(String(format: "%.1f", (t4 - t3b) * 1000)) ms")
        print("[PaintPaletteBuilder] Total execution took \(String(format: "%.1f", (t4 - t0) * 1000)) ms")
        onProgress?(0.95)
        
        return PaintPaletteResult(
            selectedTubes: selectedTubes,
            recipes: prunedRecipes,
            pixelLabels: workingLabels,
            clusterPixelCounts: finalCounts,
            clippedRecipeIndices: clippedIndices
        )
    }
    
    private static func snapAndReassign(
        recipes: [PigmentRecipe],
        pixelLab: [Float],
        selectedTubes: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int,
        minConcentration: Float,
        iterations: Int = 2
    ) -> (recipes: [PigmentRecipe], labels: [Int32], counts: [Int]) {
        var currentRecipes = recipes
        var currentCentroids = recipes.map { $0.predictedColor }

        for _ in 0..<iterations {
            // Reassign all pixels to snapped centroids (recipe predicted colors)
            let newLabels = ColorRegionsProcessor.reassignLabels(
                pixelLab: pixelLab,
                centroids: currentCentroids,
                lWeight: 0.3
            )

            // Recompute centroids and counts from new labels
            let (newCentroids, newCounts) = ColorRegionsProcessor.computeCentroidsAndCounts(
                pixelLab: pixelLab,
                labels: newLabels,
                k: currentCentroids.count
            )

            // Re-decompose only centroids that moved significantly (or became empty)
            var updatedRecipes = currentRecipes
            for i in 0..<newCentroids.count {
                guard newCounts[i] > 0 else { continue }
                let moved = oklabDistance(newCentroids[i], currentCentroids[i])
                if moved > 0.0001 { // oklabDistance is squared; 0.0001 = 0.01² (linear Oklab units)
                    let reDecomposed = PigmentDecomposer.decompose(
                        targetColors: [newCentroids[i]],
                        pigments: selectedTubes,
                        database: database,
                        maxPigments: maxPigments,
                        minConcentration: minConcentration,
                        concurrent: false
                    )
                    if let recipe = reDecomposed.first {
                        updatedRecipes[i] = recipe
                    }
                }
            }

            currentRecipes = updatedRecipes
            currentCentroids = currentRecipes.map { $0.predictedColor }
        }

        // Final reassignment to ensure labels align with recipe predicted colors
        let finalLabels = ColorRegionsProcessor.reassignLabels(
            pixelLab: pixelLab,
            centroids: currentCentroids,
            lWeight: 0.3
        )
        let (_, finalCounts) = ColorRegionsProcessor.computeCentroidsAndCounts(
            pixelLab: pixelLab,
            labels: finalLabels,
            k: currentCentroids.count
        )

        return (currentRecipes, finalLabels, finalCounts)
    }

    private static func pruneToMaxShades(
        recipes: [PigmentRecipe],
        counts: [Int],
        labels: inout [Int32],
        maxShades: Int
    ) -> [PigmentRecipe] {
        var survivors = Array(0..<recipes.count)
        
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
