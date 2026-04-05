import Testing
import UIKit
import SwiftUI
@testable import Underpaint

// MARK: - ContourGenerator tests

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

@Test
func contourGeneratorReturnsEmptyForEmptyImage() {
    let segments = ContourGenerator.generateSegments(
        depthMap: UIImage(),
        levels: 5,
        depthRange: 0...1,
        backgroundCutoff: 1.0
    )
    #expect(segments.isEmpty)
}

@Test
func contourGeneratorReturnsEmptyForZeroLevels() {
    let depthMap = TestImageFactory.makeHorizontalDepthRamp(width: 32, height: 32)
    let segments = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 0,
        depthRange: 0...1,
        backgroundCutoff: 1.0
    )
    #expect(segments.isEmpty)
}

@Test
func contourGeneratorReturnsEmptyForCollapsedRange() {
    let depthMap = TestImageFactory.makeHorizontalDepthRamp(width: 32, height: 32)
    let segments = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 5,
        depthRange: 0.5...0.5,
        backgroundCutoff: 1.0
    )
    #expect(segments.isEmpty)
}

@Test
func contourGeneratorReturnsEmptyForUniformDepth() {
    // A solid gray image has uniform depth — no isolines should be generated
    let depthMap = TestImageFactory.makeSolid(width: 32, height: 32, color: .gray)
    let segments = ContourGenerator.generateSegments(
        depthMap: depthMap,
        levels: 5,
        depthRange: 0...1,
        backgroundCutoff: 1.0,
        smoothContours: false
    )
    // Uniform image shouldn't cross any threshold
    #expect(segments.isEmpty)
}

@Test
func moreLevelsProduceMoreContours() {
    let depthMap = makeDiagonalDepthRamp(width: 64, height: 64)

    let fewLevels = ContourGenerator.generateSegments(
        depthMap: depthMap, levels: 2, depthRange: 0...1,
        backgroundCutoff: 1.0, smoothContours: false
    )
    let manyLevels = ContourGenerator.generateSegments(
        depthMap: depthMap, levels: 10, depthRange: 0...1,
        backgroundCutoff: 1.0, smoothContours: false
    )
    #expect(manyLevels.count > fewLevels.count)
}

@Test
func backgroundCutoffSkipsBackgroundRegion() {
    let depthMap = makeDiagonalDepthRamp(width: 64, height: 64)

    // Very tight cutoff restricts the visible range to near-zero values,
    // which means very few cells are non-background
    let tightCutoff = ContourGenerator.generateSegments(
        depthMap: depthMap, levels: 3, depthRange: 0...1,
        backgroundCutoff: 0.05, smoothContours: false
    )
    let wideCutoff = ContourGenerator.generateSegments(
        depthMap: depthMap, levels: 3, depthRange: 0...1,
        backgroundCutoff: 1.0, smoothContours: false
    )
    // With a very tight cutoff most of the image is background, producing fewer segments
    #expect(wideCutoff.count > tightCutoff.count)
}

@Test
func unsmoothContourHasNoDegenerate() {
    let depthMap = makeDiagonalDepthRamp(width: 64, height: 64)
    let segments = ContourGenerator.generateSegments(
        depthMap: depthMap, levels: 5, depthRange: 0...1,
        backgroundCutoff: 1.0, smoothContours: false
    )
    for seg in segments {
        #expect(!seg.isDegenerate)
    }
}

// MARK: - GridLineSegment tests

@Test
func gridLineSegmentIsDegenerateWhenStartEqualsEnd() {
    let seg = GridLineSegment(start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5))
    #expect(seg.isDegenerate)
}

@Test
func gridLineSegmentIsNotDegenerateWhenDifferent() {
    let seg = GridLineSegment(start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 1.0, y: 1.0))
    #expect(!seg.isDegenerate)
}

@Test
func gridLineSegmentPointAtProgress() {
    let seg = GridLineSegment(start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 1.0, y: 1.0))
    let mid = seg.point(at: 0.5)
    #expect(abs(mid.x - 0.5) < 0.001)
    #expect(abs(mid.y - 0.5) < 0.001)

    let start = seg.point(at: 0.0)
    #expect(abs(start.x - 0.0) < 0.001)
    #expect(abs(start.y - 0.0) < 0.001)

    let end = seg.point(at: 1.0)
    #expect(abs(end.x - 1.0) < 0.001)
    #expect(abs(end.y - 1.0) < 0.001)
}

@Test
func gridLineSegmentMappedToRect() {
    let seg = GridLineSegment(start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 1.0, y: 1.0))
    let rect = CGRect(x: 100, y: 200, width: 300, height: 400)
    let mapped = seg.mapped(to: rect)
    #expect(abs(mapped.start.x - 100) < 0.001)
    #expect(abs(mapped.start.y - 200) < 0.001)
    #expect(abs(mapped.end.x - 400) < 0.001)
    #expect(abs(mapped.end.y - 600) < 0.001)
}

@Test
func gridLineSegmentMappedPreservesNormalized() {
    let seg = GridLineSegment(start: CGPoint(x: 0.5, y: 0.25), end: CGPoint(x: 0.75, y: 0.5))
    let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
    let mapped = seg.mapped(to: rect)
    #expect(abs(mapped.start.x - 100) < 0.001)
    #expect(abs(mapped.start.y - 25) < 0.001)
    #expect(abs(mapped.end.x - 150) < 0.001)
    #expect(abs(mapped.end.y - 50) < 0.001)
}

// MARK: - GridLineTone tests

@Test
func gridLineToneBlackProperties() {
    let tone = GridLineTone.black
    #expect(tone.luminance == 0)
    #expect(tone.color == Color.black)
}

@Test
func gridLineToneWhiteProperties() {
    let tone = GridLineTone.white
    #expect(tone.luminance == 1)
    #expect(tone.color == Color.white)
}

@Test
func gridLineToneEquality() {
    #expect(GridLineTone.black == GridLineTone.black)
    #expect(GridLineTone.white == GridLineTone.white)
    #expect(GridLineTone.black != GridLineTone.white)
}

// MARK: - Helpers

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
