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

@Test
func smoothingAddsContourDetailOnDiagonalRamp() {
    let depthMap = makeDiagonalDepthRamp(width: 64, height: 64)

    let rawSegments = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 8,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        smoothContours: false
    )

    let smoothedSegments = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 8,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        smoothContours: true
    )

    #expect(!rawSegments.isEmpty)
    #expect(smoothedSegments.count > rawSegments.count)
}

@Test
func smoothedSegmentsRemainBoundedAndNonDegenerate() {
    let depthMap = makeDiagonalDepthRamp(width: 64, height: 64)

    let smoothedSegments = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 10,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        smoothContours: true
    )

    #expect(!smoothedSegments.isEmpty)

    for segment in smoothedSegments {
        #expect(!segment.isDegenerate)
        #expect((0...1).contains(segment.start.x))
        #expect((0...1).contains(segment.start.y))
        #expect((0...1).contains(segment.end.x))
        #expect((0...1).contains(segment.end.y))
    }
}

private func makeDiagonalDepthRamp(width: Int, height: Int) -> UIImage {
    guard width > 1, height > 1 else {
        return TestImageFactory.makeSolid(width: max(width, 1), height: max(height, 1), color: .black)
    }

    var data: [UInt8] = []
    data.reserveCapacity(width * height * 4)

    let denom = Double((width - 1) + (height - 1))
    for y in 0..<height {
        for x in 0..<width {
            let diagonal = (Double(x) + Double(y)) / denom
            let value = UInt8((diagonal * 255).rounded())
            data.append(value)
            data.append(value)
            data.append(value)
            data.append(255)
        }
    }

    return UIImage.fromPixelData(data, width: width, height: height)
        ?? TestImageFactory.makeSolid(width: width, height: height, color: .black)
}
