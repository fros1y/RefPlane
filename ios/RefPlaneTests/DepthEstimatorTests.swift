import UIKit
import Testing
@testable import Underpaint

@Suite
struct DepthEstimatorTests {
    @Test
    func extractEmbeddedDepthReturnsNilForPlainPNG() throws {
        let image = TestImageFactory.makeSolid(width: 40, height: 30, color: .gray)
        let data = try #require(image.pngData())

        #expect(DepthEstimator.extractEmbeddedDepth(from: data) == nil)
    }

    @Test
    func resizeProducesCorrectDimensions() {
        let depth = TestImageFactory.makeHorizontalDepthRamp(width: 50, height: 40)
        let source = TestImageFactory.makeSolid(width: 200, height: 150, color: .gray)

        let resized = DepthEstimator.resize(depth, toMatch: source)

        #expect(resized.cgImage?.width == 200)
        #expect(resized.cgImage?.height == 150)
    }
}