import Testing
import UIKit
@testable import Underpaint

@Test
func isolinesGenerateSegmentsOnDepthRamp() {
    let depthMap = TestImageFactory.makeHorizontalDepthRamp(width: 64, height: 64)

    let segments = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 6,
        depthRange: 0...1,
        backgroundCutoff: 1.0
    )

    #expect(!segments.isEmpty)
}
