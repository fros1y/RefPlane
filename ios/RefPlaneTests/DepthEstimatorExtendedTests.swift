import UIKit
import Testing
@testable import Underpaint

// MARK: - DepthEstimator extended tests

@Test
func depthRangeForSolidImageIsNarrow() {
    let image = TestImageFactory.makeSolid(width: 20, height: 20, color: .gray)
    let range = DepthEstimator.depthRange(from: image)
    // Solid gray should have a very narrow range
    #expect(range.upperBound - range.lowerBound < 0.1)
}

@Test
func depthRangeForGradientIsWide() {
    let image = TestImageFactory.makeHorizontalDepthRamp(width: 50, height: 50)
    let range = DepthEstimator.depthRange(from: image)
    // A full gradient from 0 to 255 should span most of the [0,1] range
    #expect(range.upperBound - range.lowerBound > 0.5)
}

@Test
func depthRangeForEmptyImageReturnsFallback() {
    let range = DepthEstimator.depthRange(from: UIImage())
    #expect(range == 0...1)
}

@Test
func depthRangeForBlackImageIsNearZero() {
    let image = TestImageFactory.makeSolid(width: 20, height: 20, color: .black)
    let range = DepthEstimator.depthRange(from: image)
    #expect(range.lowerBound < 0.05)
    #expect(range.upperBound < 0.05)
}

@Test
func depthRangeForWhiteImageIsNearOne() {
    let image = TestImageFactory.makeSolid(width: 20, height: 20, color: .white)
    let range = DepthEstimator.depthRange(from: image)
    #expect(range.lowerBound > 0.95)
    #expect(range.upperBound > 0.95)
}

@Test
func resizeMatchesTargetDimensions() {
    let depthMap = TestImageFactory.makeSolid(width: 100, height: 80, color: .gray)
    let source = TestImageFactory.makeSolid(width: 200, height: 150, color: .red)
    let resized = DepthEstimator.resize(depthMap, toMatch: source)
    guard let cg = resized.cgImage else {
        Issue.record("resized image has no cgImage")
        return
    }
    #expect(cg.width == 200)
    #expect(cg.height == 150)
}

@Test
func resizePreservesImageWhenSameDimensions() {
    let depthMap = TestImageFactory.makeSolid(width: 50, height: 50, color: .gray)
    let source = TestImageFactory.makeSolid(width: 50, height: 50, color: .red)
    let resized = DepthEstimator.resize(depthMap, toMatch: source)
    guard let cg = resized.cgImage else {
        Issue.record("resized image has no cgImage")
        return
    }
    #expect(cg.width == 50)
    #expect(cg.height == 50)
}

@Test
func extractEmbeddedDepthReturnsNilForSyntheticPNG() {
    // A programmatically-created PNG has no embedded depth data
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    guard let data = image.pngData() else {
        Issue.record("Could not create PNG data")
        return
    }
    let result = DepthEstimator.extractEmbeddedDepth(from: data)
    #expect(result == nil)
}

@Test
func extractEmbeddedDepthReturnsNilForJPEGWithoutDepth() {
    let image = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)
    guard let data = image.jpegData(compressionQuality: 0.9) else {
        Issue.record("Could not create JPEG data")
        return
    }
    let result = DepthEstimator.extractEmbeddedDepth(from: data)
    #expect(result == nil)
}

@Test
func extractEmbeddedDepthReturnsNilForEmptyData() {
    let result = DepthEstimator.extractEmbeddedDepth(from: Data())
    #expect(result == nil)
}

// MARK: - DepthEstimatorError descriptions

@Test
func depthEstimatorErrorDescriptions() {
    #expect(DepthEstimatorError.invalidInput.errorDescription != nil)
    #expect(DepthEstimatorError.noResult.errorDescription != nil)
    #expect(DepthEstimatorError.bufferAccessFailed.errorDescription != nil)
    #expect(DepthEstimatorError.uniformDepth.errorDescription != nil)
    #expect(DepthEstimatorError.imageCreationFailed.errorDescription != nil)
    #expect(DepthEstimatorError.modelUnavailable.errorDescription != nil)
}
