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
        pigments: [PigmentData]
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
        
        // Stage 4 - Constrained Decomposition + Snap/Reassign Loop
        var workingCentroids = colorRegions.quantizedCentroids
        var workingLabels = colorRegions.pixelLabels
        var workingCounts = colorRegions.clusterPixelCounts
        var workingRecipes = prelimRecipes
        
        let iterationCount = 2
        for _ in 0..<iterationCount {
            workingRecipes = PigmentDecomposer.decompose(
                targetColors: workingCentroids,
                pigments: selectedTubes,
                database: database,
                maxPigments: config.maxPigmentsPerMix,
                minConcentration: config.minConcentration
            )
            
            let snappedColors = workingRecipes.map { $0.predictedColor }
            workingLabels = ColorRegionsProcessor.reassignLabels(
                pixelLab: colorRegions.pixelLab,
                centroids: snappedColors,
                lWeight: 1.0
            )
            
            let recomputed = ColorRegionsProcessor.computeCentroidsAndCounts(
                pixelLab: colorRegions.pixelLab,
                labels: workingLabels,
                k: snappedColors.count
            )
            
            // Only re-decompose centroids that moved significantly if we cared to track it,
            // but wholesale recompute is fast enough per iteration
            workingCentroids = recomputed.centroids
            workingCounts = recomputed.counts
        }
        
        // Final decomposition before merge
        workingRecipes = PigmentDecomposer.decompose(
            targetColors: workingCentroids,
            pigments: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )
        
        let t3 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4 (Constrained Iterations) took \(String(format: "%.1f", (t3 - t2) * 1000)) ms")
        
        // Stage 5 - Merge, Prune, and Finalize
        let (mergedRecipes, mergeMap) = PigmentDecomposer.mergeRecipes(
            recipes: workingRecipes,
            pixelCounts: workingCounts
        )
        
        // Remap working labels through the merge map
        workingLabels = workingLabels.map { Int32(mergeMap[Int($0)]) }
        
        let finalRecomputed = ColorRegionsProcessor.computeCentroidsAndCounts(
            pixelLab: colorRegions.pixelLab,
            labels: workingLabels,
            k: mergedRecipes.count
        )
        
        var finalRecipes = PigmentDecomposer.decompose(
            targetColors: finalRecomputed.centroids,
            pigments: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )
        
        // Prune down to numShades if needed
        if finalRecipes.count > config.numShades && config.numShades > 1 {
            finalRecipes = pruneToMaxShades(
                recipes: finalRecipes,
                counts: finalRecomputed.counts,
                pixelLab: colorRegions.pixelLab,
                labels: &workingLabels,
                maxShades: config.numShades,
                database: database,
                tubes: selectedTubes,
                config: config
            )
        }
        
        // Clean up any empty clusters created by pruning
        let validIndices = (0..<finalRecipes.count).filter { i in
            workingLabels.contains(Int32(i))
        }
        let prunedRecipes = validIndices.map { finalRecipes[$0] }
        let newLabelMap = Dictionary(uniqueKeysWithValues: validIndices.enumerated().map { ($1, Int32($0)) })
        workingLabels = workingLabels.map { newLabelMap[Int($0)] ?? 0 }
        
        let finalCounts = ColorRegionsProcessor.computeCentroidsAndCounts(
            pixelLab: colorRegions.pixelLab,
            labels: workingLabels,
            k: prunedRecipes.count
        ).counts
        
        // Flags
        var clippedIndices = [Int]()
        for (i, recipe) in prunedRecipes.enumerated() {
            if recipe.deltaE > 0.05 { // Materially high delta E
                clippedIndices.append(i)
            }
        }
        
        let t4 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 5 (Merge & Prune) took \(String(format: "%.1f", (t4 - t3) * 1000)) ms")
        print("[PaintPaletteBuilder] Total execution took \(String(format: "%.1f", (t4 - t0) * 1000)) ms")
        
        return PaintPaletteResult(
            selectedTubes: selectedTubes,
            recipes: prunedRecipes,
            pixelLabels: workingLabels,
            clusterPixelCounts: finalCounts,
            clippedRecipeIndices: clippedIndices
        )
    }
    
    private static func pruneToMaxShades(
        recipes: [PigmentRecipe],
        counts: [Int],
        pixelLab: [Float],
        labels: inout [Int32],
        maxShades: Int,
        database: SpectralDatabase,
        tubes: [PigmentData],
        config: ColorConfig
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
        
        // Reassign eliminated labels to nearest survivor
        let survivorRecipes = survivors.map { recipes[$0] }
        labels = ColorRegionsProcessor.reassignLabels(
            pixelLab: pixelLab,
            centroids: survivorRecipes.map { $0.predictedColor },
            lWeight: 1.0
        )
        
        // And we just return the survivor recipes, PaintPaletteResult will clean it up tightly
        return survivorRecipes
    }
}
