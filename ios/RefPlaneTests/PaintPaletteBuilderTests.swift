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
}
