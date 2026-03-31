import UIKit
import Testing
@testable import Underpaint

@Suite
struct PaintPaletteBuilderTests {
    let database = SpectralDataStore.shared
    let pigments = SpectralDataStore.essentialPigments
    
    @Test
    func buildLimitsToMaxShades() throws {
        // Create mock color regions
        let centroids = (0..<10).map { i in OklabColor(L: 0.1 * Float(i), a: 0, b: 0) }
        let labels = [Int32](repeating: 0, count: 100)
        let pixelLab = [Float](repeating: 0, count: 300)
        
        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [Int](repeating: 10, count: 10),
            clusterSalience: [Float](repeating: 1.0, count: 10)
        )
        
        var config = ColorConfig()
        config.numShades = 3
        config.numTubes = 5
        config.maxPigmentsPerMix = 3
        config.minConcentration = 0.05
        
        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )
        
        #expect(result.recipes.count <= config.numShades)
        #expect(result.selectedTubes.count <= config.numTubes)
        #expect(result.pixelLabels.count == 100)
    }

    @Test
    func vividMinorityClusterSurvivesInOverclustering() throws {
        // Construct synthetic pixel data: 90% neutral gray, 10% vivid red
        let neutralCount = 900
        let vividCount = 100
        let total = neutralCount + vividCount

        var pixelLab = [Float](repeating: 0, count: total * 3)
        // Neutral gray: L=0.5, a=0, b=0
        for i in 0..<neutralCount {
            pixelLab[i * 3] = 0.5
            pixelLab[i * 3 + 1] = 0.0
            pixelLab[i * 3 + 2] = 0.0
        }
        // Vivid red: L=0.6, a=0.2, b=0.1
        for i in neutralCount..<total {
            pixelLab[i * 3] = 0.6
            pixelLab[i * 3 + 1] = 0.2
            pixelLab[i * 3 + 2] = 0.1
        }

        // Assign labels: 0 for neutral, 1 for vivid
        let labels: [Int32] = Array(repeating: 0, count: neutralCount) + Array(repeating: 1, count: vividCount)
        let centroids = [
            OklabColor(L: 0.5, a: 0.0, b: 0.0),
            OklabColor(L: 0.6, a: 0.2, b: 0.1)
        ]

        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [neutralCount, vividCount],
            clusterSalience: [1.0, 1.8] // Vivid cluster gets higher salience
        )

        var config = ColorConfig()
        config.numShades = 2
        config.numTubes = 4
        config.maxPigmentsPerMix = 3

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )

        // The vivid red cluster must survive as a distinct recipe
        let hasVividRecipe = result.recipes.contains { recipe in
            let chroma = sqrtf(recipe.predictedColor.a * recipe.predictedColor.a + recipe.predictedColor.b * recipe.predictedColor.b)
            return chroma > 0.05
        }
        #expect(hasVividRecipe, "Vivid minority cluster should survive in final palette")
    }

    @Test
    func snapAndReassignProducesValidLabels() throws {
        // 4 distinct clusters spread across Oklab space
        let centroids = [
            OklabColor(L: 0.2, a: 0.0, b: 0.0),   // dark neutral
            OklabColor(L: 0.8, a: 0.0, b: 0.0),   // light neutral
            OklabColor(L: 0.5, a: 0.15, b: 0.0),  // reddish
            OklabColor(L: 0.5, a: -0.1, b: 0.1)   // greenish
        ]
        let pixelsPerCluster = 50
        let total = centroids.count * pixelsPerCluster

        var pixelLab = [Float](repeating: 0, count: total * 3)
        var labels = [Int32](repeating: 0, count: total)
        for (ci, centroid) in centroids.enumerated() {
            for j in 0..<pixelsPerCluster {
                let idx = ci * pixelsPerCluster + j
                pixelLab[idx * 3] = centroid.L + Float.random(in: -0.02...0.02)
                pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.02...0.02)
                pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.02...0.02)
                labels[idx] = Int32(ci)
            }
        }

        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: 4),
            clusterSalience: [Float](repeating: 1.0, count: 4)
        )

        var config = ColorConfig()
        config.numShades = 4
        config.numTubes = 5
        config.maxPigmentsPerMix = 3

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )

        // Every pixel label must be a valid recipe index
        let recipeCount = result.recipes.count
        for label in result.pixelLabels {
            #expect(label >= 0 && Int(label) < recipeCount, "Label \(label) out of range [0, \(recipeCount))")
        }

        // Pixel count should match total
        #expect(result.pixelLabels.count == total)
        #expect(result.clusterPixelCounts.reduce(0, +) == total)
    }

    @Test
    func allFinalRecipesUseOnlySelectedTubes() throws {
        let centroids = [
            OklabColor(L: 0.2, a: -0.05, b: 0.0),
            OklabColor(L: 0.5, a: 0.1, b: 0.05),
            OklabColor(L: 0.8, a: 0.0, b: -0.05),
            OklabColor(L: 0.6, a: -0.1, b: 0.1),
            OklabColor(L: 0.35, a: 0.05, b: -0.1)
        ]
        let pixelsPerCluster = 100
        let total = centroids.count * pixelsPerCluster

        var pixelLab = [Float](repeating: 0, count: total * 3)
        var labels = [Int32](repeating: 0, count: total)
        for (ci, centroid) in centroids.enumerated() {
            for j in 0..<pixelsPerCluster {
                let idx = ci * pixelsPerCluster + j
                pixelLab[idx * 3] = centroid.L + Float.random(in: -0.01...0.01)
                pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.01...0.01)
                pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.01...0.01)
                labels[idx] = Int32(ci)
            }
        }

        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: centroids.count),
            clusterSalience: [Float](repeating: 1.0, count: centroids.count)
        )

        var config = ColorConfig()
        config.numShades = 5
        config.numTubes = 4
        config.maxPigmentsPerMix = 3

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )

        let tubeIds = Set(result.selectedTubes.map { $0.id })
        for (i, recipe) in result.recipes.enumerated() {
            for comp in recipe.components {
                #expect(tubeIds.contains(comp.pigmentId),
                    "Recipe \(i) uses pigment '\(comp.pigmentName)' (\(comp.pigmentId)) which is not in selectedTubes")
            }
        }
    }

    @Test
    func nearMonochromeImageProducesFewShades() throws {
        // All clusters are very close in color — a gray image with tiny variation
        let k = 6
        let pixelsPerCluster = 100
        let total = k * pixelsPerCluster

        var pixelLab = [Float](repeating: 0, count: total * 3)
        var labels = [Int32](repeating: 0, count: total)
        var centroids = [OklabColor]()

        for ci in 0..<k {
            let L = 0.48 + 0.01 * Float(ci) // Very tight L range: 0.48 to 0.53
            centroids.append(OklabColor(L: L, a: 0.0, b: 0.0))
            for j in 0..<pixelsPerCluster {
                let idx = ci * pixelsPerCluster + j
                pixelLab[idx * 3] = L + Float.random(in: -0.005...0.005)
                pixelLab[idx * 3 + 1] = Float.random(in: -0.005...0.005)
                pixelLab[idx * 3 + 2] = Float.random(in: -0.005...0.005)
                labels[idx] = Int32(ci)
            }
        }

        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: k),
            clusterSalience: [Float](repeating: 1.0, count: k)
        )

        var config = ColorConfig()
        config.numShades = 8 // Request 8 but image only needs ~1-2
        config.numTubes = 4
        config.maxPigmentsPerMix = 3

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )

        // With near-monochrome input, adaptive pruning should collapse most shades
        #expect(result.recipes.count < k, "Near-monochrome image should not keep all \(k) distinct shades")
    }

    @Test
    func valueAnchorsPreservedAfterMergeAndPrune() throws {
        // Create clusters with a wide value range — darkest and lightest should survive
        let centroids = [
            OklabColor(L: 0.1, a: 0.0, b: 0.0),   // very dark — anchor
            OklabColor(L: 0.3, a: 0.02, b: 0.01),
            OklabColor(L: 0.5, a: 0.05, b: 0.03),
            OklabColor(L: 0.5, a: -0.05, b: -0.03),
            OklabColor(L: 0.7, a: 0.02, b: 0.01),
            OklabColor(L: 0.95, a: 0.0, b: 0.0)   // very light — anchor
        ]
        let pixelsPerCluster = 80
        let total = centroids.count * pixelsPerCluster

        var pixelLab = [Float](repeating: 0, count: total * 3)
        var labels = [Int32](repeating: 0, count: total)
        for (ci, centroid) in centroids.enumerated() {
            for j in 0..<pixelsPerCluster {
                let idx = ci * pixelsPerCluster + j
                pixelLab[idx * 3] = centroid.L + Float.random(in: -0.01...0.01)
                pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.01...0.01)
                pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.01...0.01)
                labels[idx] = Int32(ci)
            }
        }

        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: centroids.count),
            clusterSalience: [Float](repeating: 1.0, count: centroids.count)
        )

        var config = ColorConfig()
        config.numShades = 3 // Force heavy pruning
        config.numTubes = 5
        config.maxPigmentsPerMix = 3

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )

        let lightnesses = result.recipes.map { $0.predictedColor.L }
        // The input spans L=0.1 to L=0.95; after pruning to 3 shades the
        // darkest and lightest recipe must still represent the extremes.
        // We use relative checks (not absolute thresholds) so pigment gamut
        // limits don't cause false failures.
        let darkestL = lightnesses.min() ?? 1.0
        let lightestL = lightnesses.max() ?? 0.0
        let valueRange = lightestL - darkestL

        #expect(valueRange > 0.3, "Surviving recipes should span a wide value range (got \(valueRange)); anchors may have been pruned")
        #expect(result.recipes.count >= 2, "Should have at least 2 recipes after pruning")
    }

    @Test
    func duplicateDarkRecipesMerge() throws {
        // Multiple dark clusters that should all map to the same dark pigment mix
        let centroids = [
            OklabColor(L: 0.08, a: 0.0, b: 0.0),
            OklabColor(L: 0.10, a: 0.01, b: 0.0),
            OklabColor(L: 0.12, a: 0.0, b: 0.01),
            OklabColor(L: 0.6, a: 0.1, b: 0.05)   // one distinct mid-tone
        ]
        let pixelsPerCluster = 100
        let total = centroids.count * pixelsPerCluster

        var pixelLab = [Float](repeating: 0, count: total * 3)
        var labels = [Int32](repeating: 0, count: total)
        for (ci, centroid) in centroids.enumerated() {
            for j in 0..<pixelsPerCluster {
                let idx = ci * pixelsPerCluster + j
                pixelLab[idx * 3] = centroid.L + Float.random(in: -0.005...0.005)
                pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.005...0.005)
                pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.005...0.005)
                labels[idx] = Int32(ci)
            }
        }

        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: centroids.count),
            clusterSalience: [Float](repeating: 1.0, count: centroids.count)
        )

        var config = ColorConfig()
        config.numShades = 8
        config.numTubes = 4
        config.maxPigmentsPerMix = 3

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )

        // The 3 near-identical dark clusters should merge into 1 or 2 at most
        let darkRecipes = result.recipes.filter { $0.predictedColor.L < 0.25 }
        #expect(darkRecipes.count <= 2, "Near-identical dark clusters should merge, got \(darkRecipes.count)")
        #expect(result.recipes.count >= 2, "Should still have at least 2 distinct recipes (dark + mid)")
    }

    @Test
    func clippedRecipesAreFlagged() throws {
        // Include a highly saturated color that's hard to mix with limited tubes
        let centroids = [
            OklabColor(L: 0.5, a: 0.0, b: 0.0),       // neutral — easy
            OklabColor(L: 0.7, a: 0.25, b: 0.25)       // extremely vivid — likely clipped
        ]
        let total = 200

        var pixelLab = [Float](repeating: 0, count: total * 3)
        var labels = [Int32](repeating: 0, count: total)
        for i in 0..<100 {
            pixelLab[i * 3] = 0.5; pixelLab[i * 3 + 1] = 0.0; pixelLab[i * 3 + 2] = 0.0
            labels[i] = 0
        }
        for i in 100..<200 {
            pixelLab[i * 3] = 0.7; pixelLab[i * 3 + 1] = 0.25; pixelLab[i * 3 + 2] = 0.25
            labels[i] = 1
        }

        let regions = ColorRegionsProcessor.Result(
            image: UIImage(),
            palette: [],
            paletteBands: [],
            pixelBands: [],
            quantizedCentroids: centroids,
            pixelLabels: labels,
            pixelLab: pixelLab,
            clusterPixelCounts: [100, 100],
            clusterSalience: [1.0, 1.5]
        )

        var config = ColorConfig()
        config.numShades = 2
        config.numTubes = 3 // Very limited tube budget
        config.maxPigmentsPerMix = 2

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: pigments
        )

        // clippedRecipeIndices should only contain valid indices
        // and those recipes should have materially high deltaE
        for idx in result.clippedRecipeIndices {
            #expect(idx >= 0 && idx < result.recipes.count, "Clipped index \(idx) out of range")
            #expect(result.recipes[idx].deltaE > 0.05, "Clipped recipe should have materially high deltaE")
        }
    }
}
