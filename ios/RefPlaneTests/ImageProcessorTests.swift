import UIKit
import SwiftUI
import Testing
@testable import Underpaint

// MARK: - ImageProcessor tests
//
// These tests exercise the actor-based coordinator with small synthetic images.
// The underlying processors (GrayscaleProcessor, ValueStudyProcessor, etc.)
// have dedicated test suites — these tests verify the coordinator wiring.

@Test
func processOriginalModeReturnsInputImage() async throws {
    let processor = ImageProcessor()
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let result = try await processor.process(
        image: image,
        mode: .original,
        valueConfig: ValueConfig(),
        colorConfig: ColorConfig(),
        onProgress: { _ in }
    )
    // Original mode should return the input image unchanged
    #expect(result.palette.isEmpty)
    #expect(result.paletteBands.isEmpty)
    #expect(result.pixelBands.isEmpty)
    #expect(result.pigmentRecipes == nil)
}

@Test
func processTonalModeReturnsGrayscaleImage() async throws {
    let processor = ImageProcessor()
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    var valueConfig = ValueConfig()
    valueConfig.grayscaleConversion = .luminance
    let result = try await processor.process(
        image: image,
        mode: .tonal,
        valueConfig: valueConfig,
        colorConfig: ColorConfig(),
        onProgress: { _ in }
    )
    // Tonal mode produces grayscale — R==G==B for every pixel
    guard let (pixels, _, _) = result.image.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i] == pixels[i + 1])
        #expect(pixels[i] == pixels[i + 2])
    }
    #expect(result.palette.isEmpty)
}

@Test
func processValueModeReturnsQuantizedResult() async throws {
    let processor = ImageProcessor()
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .gray)
    var valueConfig = ValueConfig()
    valueConfig.levels = 3
    valueConfig.grayscaleConversion = .luminance
    var colorConfig = ColorConfig()
    colorConfig.paletteSelectionEnabled = false
    let result = try await processor.process(
        image: image,
        mode: .value,
        valueConfig: valueConfig,
        colorConfig: colorConfig,
        onProgress: { _ in }
    )
    #expect(!result.palette.isEmpty)
    #expect(result.palette.count <= 3)
    #expect(result.pixelBands.count == 10 * 10)
}

@Test
func processColorModeReturnsColorRegions() async throws {
    let processor = ImageProcessor()
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)
    var colorConfig = ColorConfig()
    colorConfig.numShades = 3
    colorConfig.paletteSelectionEnabled = false
    let result = try await processor.process(
        image: image,
        mode: .color,
        valueConfig: ValueConfig(),
        colorConfig: colorConfig,
        onProgress: { _ in }
    )
    #expect(!result.palette.isEmpty)
    #expect(result.pixelBands.count == 10 * 10)
}

@Test
func processProgressCallbackIsCalled() async throws {
    let processor = ImageProcessor()
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    var progressValues: [Double] = []
    _ = try await processor.process(
        image: image,
        mode: .tonal,
        valueConfig: ValueConfig(),
        colorConfig: ColorConfig(),
        onProgress: { p in progressValues.append(p) }
    )
    // At least the initial and final progress should be reported
    #expect(!progressValues.isEmpty)
    #expect(progressValues.last == 1.0)
}

@Test
func processValueModeWithGradientImage() async throws {
    let processor = ImageProcessor()
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 10)
    var valueConfig = ValueConfig()
    valueConfig.levels = 4
    valueConfig.grayscaleConversion = .luminance
    var colorConfig = ColorConfig()
    colorConfig.paletteSelectionEnabled = false
    let result = try await processor.process(
        image: image,
        mode: .value,
        valueConfig: valueConfig,
        colorConfig: colorConfig,
        onProgress: { _ in }
    )
    // A gradient should produce multiple bands
    #expect(result.palette.count > 1)
    let uniqueBands = Set(result.pixelBands)
    #expect(uniqueBands.count > 1)
}

@Test
func processEmptyImageThrowsConversionFailed() async {
    let processor = ImageProcessor()
    let empty = UIImage()
    var valueConfig = ValueConfig()
    valueConfig.grayscaleConversion = .luminance
    do {
        _ = try await processor.process(
            image: empty,
            mode: .tonal,
            valueConfig: valueConfig,
            colorConfig: ColorConfig(),
            onProgress: { _ in }
        )
        Issue.record("Expected ProcessingError.conversionFailed")
    } catch {
        // Expected — empty image has no pixel data
    }
}

@Test
func processColorModePixelBandsInRange() async throws {
    let processor = ImageProcessor()
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .orange)
    var colorConfig = ColorConfig()
    colorConfig.numShades = 5
    colorConfig.paletteSelectionEnabled = false
    let result = try await processor.process(
        image: image,
        mode: .color,
        valueConfig: ValueConfig(),
        colorConfig: colorConfig,
        onProgress: { _ in }
    )
    let maxBand = result.palette.count
    for band in result.pixelBands {
        #expect(band >= 0)
        #expect(band < maxBand)
    }
}
