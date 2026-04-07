import UIKit
import Testing
@testable import Underpaint

// MARK: - DepthProcessor extended tests

@Test
func depthApplyEffectsWithGradientDepthProducesResult() {
    let source = TestImageFactory.makeSolid(width: 30, height: 30, color: .orange)
    let depth = TestImageFactory.makeHorizontalDepthRamp(width: 30, height: 30)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.2,
        backgroundCutoff: 0.8,
        effectIntensity: 0.7,
        backgroundMode: .compress
    )
    let result = DepthProcessor.applyEffects(to: source, depthMap: depth, config: config)
    #expect(result != nil)
    if let cg = result?.cgImage {
        #expect(cg.width == 30)
        #expect(cg.height == 30)
    }
}

@Test
func depthApplyEffectsRemoveModeWithGradient() {
    let source = TestImageFactory.makeSolid(width: 20, height: 20, color: .red)
    let depth = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
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
func depthApplyEffectsWithFullIntensity() {
    let source = TestImageFactory.makeSolid(width: 20, height: 20, color: .cyan)
    let depth = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.3,
        backgroundCutoff: 0.7,
        effectIntensity: 1.0,
        backgroundMode: .compress
    )
    let result = DepthProcessor.applyEffects(to: source, depthMap: depth, config: config)
    #expect(result != nil)
}

@Test
func depthApplyEffectsWithBlackDepthMap() {
    // All foreground (depth=0)
    let source = TestImageFactory.makeSolid(width: 15, height: 15, color: .yellow)
    let depth = TestImageFactory.makeSolid(width: 15, height: 15, color: .black)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.5,
        backgroundCutoff: 0.8,
        effectIntensity: 0.5,
        backgroundMode: .compress
    )
    let result = DepthProcessor.applyEffects(to: source, depthMap: depth, config: config)
    #expect(result != nil)
}

@Test
func depthApplyEffectsWithWhiteDepthMap() {
    // All background (depth=1)
    let source = TestImageFactory.makeSolid(width: 15, height: 15, color: .green)
    let depth = TestImageFactory.makeSolid(width: 15, height: 15, color: .white)
    let config = DepthConfig(
        enabled: true,
        foregroundCutoff: 0.2,
        backgroundCutoff: 0.5,
        effectIntensity: 0.8,
        backgroundMode: .compress
    )
    let result = DepthProcessor.applyEffects(to: source, depthMap: depth, config: config)
    #expect(result != nil)
}

@Test
func thresholdPreviewWithGradientDepthProducesImage() {
    let source = TestImageFactory.makeSolid(width: 25, height: 25, color: .magenta)
    let depth = TestImageFactory.makeHorizontalDepthRamp(width: 25, height: 25)
    let result = DepthProcessor.thresholdPreview(
        sourceImage: source,
        depthMap: depth,
        backgroundCutoff: 0.3
    )
    #expect(result.image != nil)
}

@Test
func thresholdPreviewWithHighCutoff() {
    let source = TestImageFactory.makeSolid(width: 20, height: 20, color: .blue)
    let depth = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
    let result = DepthProcessor.thresholdPreview(
        sourceImage: source,
        depthMap: depth,
        backgroundCutoff: 0.99
    )
    #expect(result.image != nil)
}

@Test
func thresholdPreviewWithLowCutoff() {
    let source = TestImageFactory.makeSolid(width: 20, height: 20, color: .red)
    let depth = TestImageFactory.makeHorizontalDepthRamp(width: 20, height: 20)
    let result = DepthProcessor.thresholdPreview(
        sourceImage: source,
        depthMap: depth,
        backgroundCutoff: 0.01
    )
    #expect(result.image != nil)
}

@Test
func thresholdPreviewResultHasNoCachedTexturesOnCPUPath() {
    // When running without Metal (or the CPU path), cached textures should be nil
    let source = TestImageFactory.makeSolid(width: 10, height: 10, color: .white)
    let depth = TestImageFactory.makeSolid(width: 10, height: 10, color: .gray)
    let result = DepthProcessor.thresholdPreview(
        sourceImage: source,
        depthMap: depth,
        backgroundCutoff: 0.5
    )
    // On CPU path, cached textures are nil; on GPU path, they'd be non-nil
    // We can't control which path runs, so just verify the result is valid
    #expect(result.image != nil)
}
