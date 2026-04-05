import UIKit
import Testing
@testable import Underpaint

// MARK: - ValueStudyProcessor extended tests

@Test
func valueProcessorReturnsNilForEmptyImage() {
    let config = ValueConfig()
    let result = ValueStudyProcessor.process(image: UIImage(), config: config)
    #expect(result == nil)
}

@Test
func processWithTwoLevelsProducesTwoBands() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
    var config = ValueConfig()
    config.levels = 2
    config.thresholds = defaultThresholds(for: 2)
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        #expect(r.levelColors.count == 2)
        let uniqueBands = Set(r.pixelBands)
        #expect(uniqueBands.count <= 2)
    }
}

@Test
func processWithEightLevelsProducesMoreBands() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 30, height: 30)
    var config = ValueConfig()
    config.levels = 8
    config.thresholds = defaultThresholds(for: 8)
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        #expect(r.levelColors.count == 8)
        let uniqueBands = Set(r.pixelBands)
        #expect(uniqueBands.count > 1)
    }
}

@Test
func processPixelBandsMatchDimensions() {
    let w = 15
    let h = 10
    let image = TestImageFactory.makeSolid(width: w, height: h, color: .gray)
    var config = ValueConfig()
    config.levels = 3
    config.thresholds = defaultThresholds(for: 3)
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
    #expect(result?.pixelBands.count == w * h)
}

@Test
func processWithRegionCleanup() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 30, height: 30)
    var config = ValueConfig()
    config.levels = 4
    config.thresholds = defaultThresholds(for: 4)
    let result = ValueStudyProcessor.process(image: image, config: config, minRegionSize: .medium)
    #expect(result != nil)
}

@Test
func processLevelColorsAreGrayscale() {
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)
    var config = ValueConfig()
    config.levels = 4
    config.thresholds = defaultThresholds(for: 4)
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        for color in r.levelColors {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            // Grayscale means R==G==B
            #expect(abs(red - green) < 0.01)
            #expect(abs(red - blue) < 0.01)
        }
    }
}

@Test
func processLevelColorsAreMonotonicallyIncreasing() {
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .gray)
    var config = ValueConfig()
    config.levels = 5
    config.thresholds = defaultThresholds(for: 5)
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        var previousBrightness: CGFloat = -1
        for color in r.levelColors {
            var white: CGFloat = 0, alpha: CGFloat = 0
            color.getWhite(&white, alpha: &alpha)
            #expect(white >= previousBrightness)
            previousBrightness = white
        }
    }
}

@Test
func processBandsAreInRange() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
    var config = ValueConfig()
    config.levels = 5
    config.thresholds = defaultThresholds(for: 5)
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let r = result {
        for band in r.pixelBands {
            #expect(band >= 0)
            #expect(band < 5)
        }
    }
}

@Test
func processOutputImageMatchesDimensions() {
    let w = 25
    let h = 15
    let image = TestImageFactory.makeSolid(width: w, height: h, color: .cyan)
    var config = ValueConfig()
    config.levels = 3
    config.thresholds = defaultThresholds(for: 3)
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
    if let cg = result?.image.cgImage {
        #expect(cg.width == w)
        #expect(cg.height == h)
    }
}

@Test
func processWithAverageConversion() {
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    var config = ValueConfig()
    config.levels = 3
    config.thresholds = defaultThresholds(for: 3)
    config.grayscaleConversion = .average
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
}

@Test
func processWithLightnessConversion() {
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)
    var config = ValueConfig()
    config.levels = 3
    config.thresholds = defaultThresholds(for: 3)
    config.grayscaleConversion = .lightness
    let result = ValueStudyProcessor.process(image: image, config: config)
    #expect(result != nil)
}
