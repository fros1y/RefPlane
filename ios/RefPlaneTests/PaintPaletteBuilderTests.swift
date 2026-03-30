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
}
