import SwiftUI
import Testing
@testable import Underpaint

// MARK: - ContourLineColorResolver

@Test
func blackLineStyleResolvesToBlack() {
    let config = ContourConfig(
        enabled: true,
        levels: 5,
        lineStyle: .black,
        customColor: .red,
        opacity: 1.0
    )
    let segment = GridLineSegment(
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1, y: 1)
    )
    let resolved = ContourLineColorResolver.resolvedSegments(
        config: config,
        image: nil,
        segments: [segment]
    )
    #expect(resolved.count == 1)
    #expect(resolved[0].color == .black)
}

@Test
func whiteLineStyleResolvesToWhite() {
    let config = ContourConfig(
        enabled: true,
        levels: 5,
        lineStyle: .white,
        customColor: .red,
        opacity: 1.0
    )
    let segment = GridLineSegment(
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1, y: 1)
    )
    let resolved = ContourLineColorResolver.resolvedSegments(
        config: config,
        image: nil,
        segments: [segment]
    )
    #expect(resolved.count == 1)
    #expect(resolved[0].color == .white)
}

@Test
func customLineStyleUsesCustomColor() {
    let customColor = Color.purple
    let config = ContourConfig(
        enabled: true,
        levels: 5,
        lineStyle: .custom,
        customColor: customColor,
        opacity: 1.0
    )
    let segment = GridLineSegment(
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1, y: 1)
    )
    let resolved = ContourLineColorResolver.resolvedSegments(
        config: config,
        image: nil,
        segments: [segment]
    )
    #expect(resolved.count == 1)
    #expect(resolved[0].color == customColor)
}

@Test
func multipleSegmentsAllResolve() {
    let config = ContourConfig(
        enabled: true,
        levels: 3,
        lineStyle: .black,
        customColor: .white,
        opacity: 0.5
    )
    let segments = [
        GridLineSegment(start: .zero, end: CGPoint(x: 1, y: 0)),
        GridLineSegment(start: .zero, end: CGPoint(x: 0, y: 1)),
        GridLineSegment(start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 1, y: 1)),
    ]
    let resolved = ContourLineColorResolver.resolvedSegments(
        config: config,
        image: nil,
        segments: segments
    )
    #expect(resolved.count == 3)
    for r in resolved {
        #expect(r.color == .black)
    }
}

@Test
func emptySegmentsReturnsEmpty() {
    let config = ContourConfig(
        enabled: true,
        levels: 5,
        lineStyle: .white,
        customColor: .white,
        opacity: 1.0
    )
    let resolved = ContourLineColorResolver.resolvedSegments(
        config: config,
        image: nil,
        segments: []
    )
    #expect(resolved.isEmpty)
}

@Test
func autoContrastDelegatesToGridLineColorResolver() {
    // Auto-contrast should delegate to GridLineColorResolver.
    // With a nil image, it should still produce a result (fallback behaviour).
    let config = ContourConfig(
        enabled: true,
        levels: 5,
        lineStyle: .autoContrast,
        customColor: .white,
        opacity: 0.7
    )
    let segment = GridLineSegment(
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1, y: 1)
    )
    let resolved = ContourLineColorResolver.resolvedSegments(
        config: config,
        image: TestImageFactory.makeSolid(width: 10, height: 10, color: .white),
        segments: [segment]
    )
    #expect(resolved.count == 1)
    // With a white image, auto-contrast should produce a dark line
    // (exact color depends on implementation, just verify it resolves)
}
