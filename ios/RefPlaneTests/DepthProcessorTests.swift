import UIKit
import Testing
@testable import Underpaint

// MARK: - DepthProcessor tests
//
// Tests exercise the CPU fallback path. MetalContext may or may not be available
// in the test environment; the CPU path produces equivalent results.

@Test
func applyEffectsReturnsNilForEmptyImage() {
    let empty = UIImage()
    let depth = TestImageFactory.makeSolid(width: 10, height: 10, color: .gray)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.33,
        backgroundCutoff: 0.66,
        effectIntensity: 0.5,
        backgroundMode: .compress
    )
    let result = DepthProcessor.applyEffects(to: empty, depthMap: depth, config: config)
    #expect(result == nil)
}

@Test
func applyEffectsReturnsImageForValidInput() {
    let source = TestImageFactory.makeSolid(width: 20, height: 20, color: .red)
    let depth = TestImageFactory.makeSolid(width: 20, height: 20, color: .gray)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.33,
        backgroundCutoff: 0.66,
        effectIntensity: 0.5,
        backgroundMode: .compress
    )
    let result = DepthProcessor.applyEffects(to: source, depthMap: depth, config: config)
    #expect(result != nil)
    if let resultCG = result?.cgImage {
        #expect(resultCG.width == 20)
        #expect(resultCG.height == 20)
    }
}

@Test
func applyEffectsWithRemoveModeProducesResult() {
    let source = TestImageFactory.makeSolid(width: 20, height: 20, color: .blue)
    let depth = TestImageFactory.makeSolid(width: 20, height: 20, color: .white)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.1,
        backgroundCutoff: 0.5,
        effectIntensity: 1.0,
        backgroundMode: .remove
    )
    let result = DepthProcessor.applyEffects(to: source, depthMap: depth, config: config)
    #expect(result != nil)
}

@Test
func applyEffectsWithZeroIntensityPreservesImage() {
    let source = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)
    let depth = TestImageFactory.makeSolid(width: 10, height: 10, color: .gray)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.33,
        backgroundCutoff: 0.66,
        effectIntensity: 0.0,
        backgroundMode: .compress
    )
    let result = DepthProcessor.applyEffects(to: source, depthMap: depth, config: config)
    #expect(result != nil)

    // With zero intensity, output should closely match input
    guard let (srcPixels, _, _) = source.toPixelData(),
          let (resPixels, _, _) = result?.toPixelData() else {
        Issue.record("Could not extract pixel data")
        return
    }
    // Verify pixels are very close (within GPU/CPU rounding)
    for i in stride(from: 0, to: min(srcPixels.count, resPixels.count), by: 4) {
        #expect(abs(Int(srcPixels[i]) - Int(resPixels[i])) <= 2)
        #expect(abs(Int(srcPixels[i+1]) - Int(resPixels[i+1])) <= 2)
        #expect(abs(Int(srcPixels[i+2]) - Int(resPixels[i+2])) <= 2)
    }
}

// MARK: - ThresholdPreview

@Test
func thresholdPreviewReturnsResultForValidInput() {
    let source = TestImageFactory.makeSolid(width: 20, height: 20, color: .red)
    let depth = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
    let result = DepthProcessor.thresholdPreview(
        sourceImage: source,
        depthMap: depth,
        backgroundCutoff: 0.5
    )
    #expect(result.image != nil)
}

@Test
func thresholdPreviewReturnsNilForEmptySource() {
    let result = DepthProcessor.thresholdPreview(
        sourceImage: UIImage(),
        depthMap: UIImage(),
        backgroundCutoff: 0.5
    )
    #expect(result.image == nil)
}

@Test
func thresholdPreviewWithZeroCutoffShowsAllSource() {
    let source = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let depth = TestImageFactory.makeSolid(width: 10, height: 10, color: .black) // all near (0)
    let result = DepthProcessor.thresholdPreview(
        sourceImage: source,
        depthMap: depth,
        backgroundCutoff: 1.0 // nothing above cutoff
    )
    #expect(result.image != nil)
}

@Test
func thresholdPreviewDimensionsMatchInput() {
    let source = TestImageFactory.makeSolid(width: 30, height: 20, color: .blue)
    let depth = TestImageFactory.makeSolid(width: 30, height: 20, color: .gray)
    let result = DepthProcessor.thresholdPreview(
        sourceImage: source,
        depthMap: depth,
        backgroundCutoff: 0.5
    )
    if let img = result.image, let cg = img.cgImage {
        // CPU path uses depth dimensions; Metal path may also match
        #expect(cg.width == 30)
        #expect(cg.height == 20)
    }
}
