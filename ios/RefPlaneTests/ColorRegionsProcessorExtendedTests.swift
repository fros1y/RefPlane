import UIKit
import SwiftUI
import Testing
@testable import Underpaint

// MARK: - ColorRegionsProcessor extended tests

@Test
func colorProcessWithGradientImage() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 30, height: 30)
    var config = ColorConfig()
    config.numShades = 5
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        #expect(r.palette.count == 5)
        #expect(r.quantizedCentroids.count == 5)
        #expect(r.pixelBands.count == 30 * 30)
    }
}

@Test
func colorProcessWithTwoShades() {
    let image = TestImageFactory.makeSolid(width: 20, height: 20, color: .blue)
    var config = ColorConfig()
    config.numShades = 2
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        #expect(r.palette.count == 2)
    }
}

@Test
func colorProcessWithMaxShades() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 40, height: 40)
    var config = ColorConfig()
    config.numShades = 12
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        #expect(r.palette.count == 12)
    }
}

@Test
func colorProcessPixelLabArrayIsCorrectSize() {
    let w = 20
    let h = 15
    let image = TestImageFactory.makeSolid(width: w, height: h, color: .yellow)
    var config = ColorConfig()
    config.numShades = 3
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        // pixelLab has 3 floats (L,a,b) per pixel
        #expect(r.pixelLab.count == w * h * 3)
    }
}

@Test
func colorProcessClusterSalienceIsNonNegative() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 30, height: 30)
    var config = ColorConfig()
    config.numShades = 4
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        for s in r.clusterSalience {
            #expect(s >= 0)
        }
    }
}

@Test
func colorProcessPaletteBandsAreSequential() {
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    var config = ColorConfig()
    config.numShades = 5
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        // paletteBands should be [0, 1, 2, 3, 4]
        #expect(r.paletteBands == Array(0..<5))
    }
}

@Test
func colorProcessWithSmallRegionCleanup() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 40, height: 40)
    var config = ColorConfig()
    config.numShades = 6
    let resultOff = ColorRegionsProcessor.process(image: image, config: config, minRegionSize: .off)
    let resultSmall = ColorRegionsProcessor.process(image: image, config: config, minRegionSize: .small)
    let resultLarge = ColorRegionsProcessor.process(image: image, config: config, minRegionSize: .large)
    #expect(resultOff != nil)
    #expect(resultSmall != nil)
    #expect(resultLarge != nil)
}

@Test
func colorProcessWithOverclusterKReturnsMoreShades() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 30, height: 30)
    var config = ColorConfig()
    config.numShades = 3
    let result = ColorRegionsProcessor.process(image: image, config: config, overclusterK: 10)
    #expect(result != nil)
    if let r = result {
        // overclusterK overrides numShades
        #expect(r.palette.count == 10)
    }
}

@Test
func colorProcessWithQuantizationBias() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
    var configBright = ColorConfig()
    configBright.numShades = 4
    configBright.quantizationBias = 1.0 // brighter bias
    let resultBright = ColorRegionsProcessor.process(image: image, config: configBright)
    #expect(resultBright != nil)

    var configDarker = ColorConfig()
    configDarker.numShades = 4
    configDarker.quantizationBias = -1.0 // darker bias
    let resultDarker = ColorRegionsProcessor.process(image: image, config: configDarker)
    #expect(resultDarker != nil)

    var configNeutral = ColorConfig()
    configNeutral.numShades = 4
    configNeutral.quantizationBias = 0.0 // neutral
    let resultNeutral = ColorRegionsProcessor.process(image: image, config: configNeutral)
    #expect(resultNeutral != nil)
}

@Test
func colorProcessWithPaletteSpread() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 30, height: 30)
    var configLow = ColorConfig()
    configLow.numShades = 4
    configLow.paletteSpread = 0.0
    let resultLow = ColorRegionsProcessor.process(image: image, config: configLow)
    #expect(resultLow != nil)

    var configHigh = ColorConfig()
    configHigh.numShades = 4
    configHigh.paletteSpread = 1.0
    let resultHigh = ColorRegionsProcessor.process(image: image, config: configHigh)
    #expect(resultHigh != nil)
}

@Test
func colorProcessWith1x1Image() {
    let image = TestImageFactory.makeSolid(width: 1, height: 1, color: .white)
    var config = ColorConfig()
    config.numShades = 2
    let result = ColorRegionsProcessor.process(image: image, config: config)
    // Should still produce a result
    #expect(result != nil)
    if let r = result {
        #expect(r.pixelLabels.count == 1)
    }
}

// MARK: - Public helper method tests

@Test
func assignQuantizedToRecipesBasic() {
    let quantized = [
        OklabColor(L: 0.2, a: 0.0, b: 0.0),
        OklabColor(L: 0.5, a: 0.0, b: 0.0),
        OklabColor(L: 0.8, a: 0.0, b: 0.0),
    ]
    let recipes = [
        OklabColor(L: 0.25, a: 0.0, b: 0.0),
        OklabColor(L: 0.75, a: 0.0, b: 0.0),
    ]
    let mapping = ColorRegionsProcessor.assignQuantizedToRecipes(
        quantizedCentroids: quantized,
        recipeCentroids: recipes,
        lWeight: 0.3
    )
    #expect(mapping.count == 3)
    // First centroid (L=0.2) should be closest to recipe 0 (L=0.25)
    #expect(mapping[0] == 0)
    // Third centroid (L=0.8) should be closest to recipe 1 (L=0.75)
    #expect(mapping[2] == 1)
}

@Test
func assignQuantizedToRecipesEmptyRecipes() {
    let quantized = [OklabColor(L: 0.5, a: 0.0, b: 0.0)]
    let mapping = ColorRegionsProcessor.assignQuantizedToRecipes(
        quantizedCentroids: quantized,
        recipeCentroids: [],
        lWeight: 0.3
    )
    #expect(mapping.count == 1)
    #expect(mapping[0] == 0) // fallback
}

@Test
func projectQuantizedLabelsBasic() {
    let pixelLabels: [Int32] = [0, 1, 2, 0, 1]
    let centroidToRecipe: [Int32] = [1, 0, 1]
    let result = ColorRegionsProcessor.projectQuantizedLabels(
        pixelQuantizedLabels: pixelLabels,
        centroidToRecipe: centroidToRecipe
    )
    #expect(result == [1, 0, 1, 1, 0])
}

@Test
func projectQuantizedLabelsEmptyMap() {
    let pixelLabels: [Int32] = [0, 1, 2]
    let result = ColorRegionsProcessor.projectQuantizedLabels(
        pixelQuantizedLabels: pixelLabels,
        centroidToRecipe: []
    )
    #expect(result == [0, 0, 0]) // all fallback to 0
}

@Test
func computeCentroidsAndCountsQuantizedBasic() {
    let quantized = [
        OklabColor(L: 0.2, a: 0.1, b: -0.1),
        OklabColor(L: 0.8, a: -0.1, b: 0.1),
    ]
    let pixelCounts = [100, 200]
    let centroidToRecipe: [Int32] = [0, 1]
    let (centroids, counts) = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
        quantizedCentroids: quantized,
        quantizedPixelCounts: pixelCounts,
        centroidToRecipe: centroidToRecipe,
        recipeCount: 2
    )
    #expect(centroids.count == 2)
    #expect(counts == [100, 200])
}

@Test
func computeCentroidsAndCountsQuantizedMerged() {
    // Two quantized centroids mapping to the same recipe
    let quantized = [
        OklabColor(L: 0.3, a: 0.0, b: 0.0),
        OklabColor(L: 0.5, a: 0.0, b: 0.0),
    ]
    let pixelCounts = [100, 100]
    let centroidToRecipe: [Int32] = [0, 0] // both map to recipe 0
    let (centroids, counts) = ColorRegionsProcessor.computeCentroidsAndCountsQuantized(
        quantizedCentroids: quantized,
        quantizedPixelCounts: pixelCounts,
        centroidToRecipe: centroidToRecipe,
        recipeCount: 1
    )
    #expect(centroids.count == 1)
    #expect(counts == [200])
    // Weighted average L: (0.3*100 + 0.5*100) / 200 = 0.4
    #expect(abs(centroids[0].L - 0.4) < 0.01)
}

@Test
func reassignLabelsProducesValidLabels() {
    // Create simple pixel lab data: 4 pixels with distinct L values
    let pixelLab: [Float] = [
        0.1, 0.0, 0.0,  // pixel 0: dark
        0.3, 0.0, 0.0,  // pixel 1: mid-dark
        0.7, 0.0, 0.0,  // pixel 2: mid-bright
        0.9, 0.0, 0.0,  // pixel 3: bright
    ]
    let centroids = [
        OklabColor(L: 0.2, a: 0.0, b: 0.0),
        OklabColor(L: 0.8, a: 0.0, b: 0.0),
    ]
    let labels = ColorRegionsProcessor.reassignLabels(
        pixelLab: pixelLab,
        centroids: centroids,
        lWeight: 0.3
    )
    #expect(labels.count == 4)
    for label in labels {
        #expect(label >= 0)
        #expect(label < 2)
    }
}

@Test
func computeCentroidsAndCountsBasic() {
    let pixelLab: [Float] = [
        0.2, 0.0, 0.0,
        0.2, 0.0, 0.0,
        0.8, 0.0, 0.0,
    ]
    let labels: [Int32] = [0, 0, 1]
    let (centroids, counts) = ColorRegionsProcessor.computeCentroidsAndCounts(
        pixelLab: pixelLab, labels: labels, k: 2
    )
    #expect(centroids.count == 2)
    #expect(counts == [2, 1])
    #expect(abs(centroids[0].L - 0.2) < 0.01)
    #expect(abs(centroids[1].L - 0.8) < 0.01)
}
