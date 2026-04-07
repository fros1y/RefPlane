import UIKit
import Testing
@testable import Underpaint

// MARK: - ColorRegionsProcessor

@Test
func processReturnsNilForEmptyImage() {
    let config = ColorConfig()
    let result = ColorRegionsProcessor.process(image: UIImage(), config: config)
    #expect(result == nil)
}

@Test
func processProducesResultForSolidImage() {
    let image = TestImageFactory.makeSolid(width: 20, height: 20, color: .red)
    var config = ColorConfig()
    config.numShades = 3
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        #expect(!r.palette.isEmpty)
        #expect(r.pixelBands.count == 20 * 20)
        #expect(r.pixelLabels.count == 20 * 20)
        #expect(r.quantizedCentroids.count == r.palette.count)
    }
}

@Test
func processProducesResultForMultiColorImage() {
    // Create a 4×1 image with distinct colors
    let pixels: [(UInt8, UInt8, UInt8)] = [
        (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0),
    ]
    let image = TestImageFactory.makeSplitColors(pixels: pixels, width: 4, height: 1)
    var config = ColorConfig()
    config.numShades = 4
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        #expect(r.pixelLabels.count == 4)
    }
}

@Test
func processWithMinRegionSizeProducesResult() {
    let image = TestImageFactory.makeSolid(width: 30, height: 30, color: .blue)
    var config = ColorConfig()
    config.numShades = 5
    let result = ColorRegionsProcessor.process(
        image: image,
        config: config,
        minRegionSize: .medium
    )
    #expect(result != nil)
}

@Test
func processOutputImageHasSameDimensions() {
    let image = TestImageFactory.makeSolid(width: 15, height: 25, color: .green)
    var config = ColorConfig()
    config.numShades = 3
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result, let cg = r.image.cgImage {
        #expect(cg.width == 15)
        #expect(cg.height == 25)
    }
}

@Test
func processPixelLabelsAreInRange() {
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .cyan)
    var config = ColorConfig()
    config.numShades = 4
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        let maxLabel = r.quantizedCentroids.count
        for label in r.pixelLabels {
            #expect(label >= 0)
            #expect(Int(label) < maxLabel)
        }
    }
}

@Test
func processWithOverclusterKProducesResult() {
    let image = TestImageFactory.makeSolid(width: 20, height: 20, color: .purple)
    var config = ColorConfig()
    config.numShades = 3
    let result = ColorRegionsProcessor.process(
        image: image,
        config: config,
        overclusterK: 8
    )
    #expect(result != nil)
}

@Test
func processClusterPixelCountsSumToTotal() {
    let width = 12
    let height = 8
    let image = TestImageFactory.makeSolid(width: width, height: height, color: .orange)
    var config = ColorConfig()
    config.numShades = 3
    let result = ColorRegionsProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        let totalPixels = r.clusterPixelCounts.reduce(0, +)
        #expect(totalPixels == width * height)
    }
}
