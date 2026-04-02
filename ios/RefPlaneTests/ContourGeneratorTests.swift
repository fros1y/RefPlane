import Testing
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
