import Testing
import UIKit
@testable import Underpaint

@Test
func projectedGridGeneratesWarpedNonAxisAlignedSegmentsOnDepthRamp() {
    let depthMap = TestImageFactory.makeHorizontalDepthRamp(width: 64, height: 64)

    let segments = ContourGenerator.generateProjectedGridSegments(
        depthMap: depthMap,
        levels: 6,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        depthScale: 4.0
    )

    #expect(!segments.isEmpty)
    #expect(segments.contains { segment in
        abs(segment.start.x - segment.end.x) > 1e-6 &&
        abs(segment.start.y - segment.end.y) > 1e-6
    })
}

@Test
func isolineAndProjectedGridModesProduceDifferentGeometry() {
    let depthMap = TestImageFactory.makeHorizontalDepthRamp(width: 64, height: 64)

    let isolines = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 6,
        depthRange: 0...1,
        backgroundCutoff: 1.0
    )

    let projectedGrid = ContourGenerator.generateProjectedGridSegments(
        depthMap: depthMap,
        levels: 6,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        depthScale: 4.0
    )

    #expect(!isolines.isEmpty)
    #expect(!projectedGrid.isEmpty)
    #expect(isolines != projectedGrid)
}

@Test
func projectedGridDepthScaleIncreasesProjectedDeviation() {
    let depthMap = TestImageFactory.makeHorizontalDepthRamp(width: 64, height: 64)

    let shallow = ContourGenerator.generateProjectedGridSegments(
        depthMap: depthMap,
        levels: 6,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        depthScale: 0.5
    )

    let deep = ContourGenerator.generateProjectedGridSegments(
        depthMap: depthMap,
        levels: 6,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        depthScale: 8.0
    )

    let shallowMaxX = shallow.map { max($0.start.x, $0.end.x) }.max() ?? 0
    let deepMaxX = deep.map { max($0.start.x, $0.end.x) }.max() ?? 0

    #expect(deepMaxX > shallowMaxX)
}

@Test
func projectedGridAvoidsLongSpuriousSegmentsAcrossBackgroundTransitions() {
    let width = 96
    let height = 96
    var data: [UInt8] = []
    data.reserveCapacity(width * height * 4)

    for _ in 0..<height {
        for x in 0..<width {
            let value: UInt8
            if x < width / 2 {
                value = UInt8((Double(x) / Double((width / 2) - 1) * 180).rounded())
            } else {
                value = 255 // background side
            }
            data.append(value)
            data.append(value)
            data.append(value)
            data.append(255)
        }
    }

    let depthMap = UIImage.fromPixelData(data, width: width, height: height)
        ?? TestImageFactory.makeSolid(width: width, height: height, color: .white)

    let segments = ContourGenerator.generateProjectedGridSegments(
        depthMap: depthMap,
        levels: 8,
        depthRange: 0...1,
        backgroundCutoff: 0.98,
        depthScale: 7.0
    )

    #expect(!segments.isEmpty)

    let maxLength = segments.reduce(0.0) { current, segment in
        let dx = Double(segment.end.x - segment.start.x)
        let dy = Double(segment.end.y - segment.start.y)
        return max(current, hypot(dx, dy))
    }

    #expect(maxLength < 0.45)
}
