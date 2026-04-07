import SwiftUI
import UIKit
import Testing
@testable import Underpaint

// MARK: - GridLineColorResolver extended tests

@Test
func normalizedSegmentsReturnsEmptyForZeroDivisions() {
    let config = GridConfig(enabled: true, divisions: 0, showDiagonals: false,
                             lineStyle: .black, customColor: .white, opacity: 1)
    let segments = GridLineColorResolver.normalizedSegments(config: config, imageSize: CGSize(width: 100, height: 100))
    #expect(segments.isEmpty)
}

@Test
func normalizedSegmentsReturnsEmptyForZeroSize() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .black, customColor: .white, opacity: 1)
    let segments = GridLineColorResolver.normalizedSegments(config: config, imageSize: .zero)
    #expect(segments.isEmpty)
}

@Test
func normalizedSegmentsProducesGridLines() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .black, customColor: .white, opacity: 1)
    let segments = GridLineColorResolver.normalizedSegments(config: config, imageSize: CGSize(width: 100, height: 100))
    #expect(!segments.isEmpty)
    // For a square image with 4 divisions: 5 vertical + 5 horizontal = 10 lines minimum
    #expect(segments.count >= 10)
}

@Test
func normalizedSegmentsWithDiagonalsHasMoreLines() {
    let withoutDiag = GridConfig(enabled: true, divisions: 3, showDiagonals: false,
                                  lineStyle: .black, customColor: .white, opacity: 1)
    let withDiag = GridConfig(enabled: true, divisions: 3, showDiagonals: true,
                               lineStyle: .black, customColor: .white, opacity: 1)
    let size = CGSize(width: 100, height: 100)

    let segWithout = GridLineColorResolver.normalizedSegments(config: withoutDiag, imageSize: size)
    let segWith = GridLineColorResolver.normalizedSegments(config: withDiag, imageSize: size)
    #expect(segWith.count > segWithout.count)
}

@Test
func normalizedSegmentsAreInNormalizedRange() {
    let config = GridConfig(enabled: true, divisions: 5, showDiagonals: true,
                             lineStyle: .black, customColor: .white, opacity: 1)
    let segments = GridLineColorResolver.normalizedSegments(
        config: config, imageSize: CGSize(width: 200, height: 150))
    for seg in segments {
        #expect(seg.start.x >= 0 && seg.start.x <= 1)
        #expect(seg.start.y >= 0 && seg.start.y <= 1)
        #expect(seg.end.x >= 0 && seg.end.x <= 1)
        #expect(seg.end.y >= 0 && seg.end.y <= 1)
    }
}

@Test
func resolvedColorBlack() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .black, customColor: .white, opacity: 1)
    #expect(GridLineColorResolver.resolvedColor(config: config, image: nil) == .black)
}

@Test
func resolvedColorWhite() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .white, customColor: .white, opacity: 1)
    #expect(GridLineColorResolver.resolvedColor(config: config, image: nil) == .white)
}

@Test
func resolvedColorCustom() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .custom, customColor: .purple, opacity: 1)
    #expect(GridLineColorResolver.resolvedColor(config: config, image: nil) == .purple)
}

@Test
func resolvedColorAutoContrastWithWhiteImage() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .autoContrast, customColor: .white, opacity: 1)
    let whiteImage = TestImageFactory.makeSolid(width: 10, height: 10, color: .white)
    let color = GridLineColorResolver.resolvedColor(config: config, image: whiteImage)
    // Against a white image, auto-contrast should choose black
    #expect(color == .black)
}

@Test
func resolvedColorAutoContrastWithBlackImage() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .autoContrast, customColor: .white, opacity: 1)
    let blackImage = TestImageFactory.makeSolid(width: 10, height: 10, color: .black)
    let color = GridLineColorResolver.resolvedColor(config: config, image: blackImage)
    // Against a black image, auto-contrast should choose white
    #expect(color == .white)
}

@Test
func autoContrastToneForBrightBackground() {
    let tone = GridLineColorResolver.autoContrastTone(forAverageLuminance: 0.9)
    #expect(tone == .black)
}

@Test
func autoContrastToneForDarkBackground() {
    let tone = GridLineColorResolver.autoContrastTone(forAverageLuminance: 0.1)
    #expect(tone == .white)
}

@Test
func autoContrastToneForNilLuminance() {
    let tone = GridLineColorResolver.autoContrastTone(forAverageLuminance: nil)
    #expect(tone == .white)
}

@Test
func contrastDistanceFromBlack() {
    let dist = GridLineColorResolver.contrastDistance(from: 0.0, to: .white)
    #expect(abs(dist - 1.0) < 0.001)
}

@Test
func contrastDistanceFromWhite() {
    let dist = GridLineColorResolver.contrastDistance(from: 1.0, to: .black)
    #expect(abs(dist - 1.0) < 0.001)
}

@Test
func contrastDistanceFromMidgray() {
    let distToBlack = GridLineColorResolver.contrastDistance(from: 0.5, to: .black)
    let distToWhite = GridLineColorResolver.contrastDistance(from: 0.5, to: .white)
    #expect(abs(distToBlack - distToWhite) < 0.001)
}

@Test
func resolvedSegmentsAutoContrastWithImage() {
    let config = GridConfig(enabled: true, divisions: 3, showDiagonals: false,
                             lineStyle: .autoContrast, customColor: .white, opacity: 1)
    let image = TestImageFactory.makeSolid(width: 20, height: 20, color: .white)
    let gridSegs = GridLineColorResolver.normalizedSegments(config: config, imageSize: CGSize(width: 20, height: 20))
    let resolved = GridLineColorResolver.resolvedSegments(config: config, image: image, segments: gridSegs)
    #expect(!resolved.isEmpty)
    // All segments on a white image should be dark/black
    for seg in resolved {
        #expect(seg.tone == .black)
    }
}

@Test
func normalizedSegmentsForRectangularImage() {
    let config = GridConfig(enabled: true, divisions: 4, showDiagonals: false,
                             lineStyle: .black, customColor: .white, opacity: 1)
    // Non-square image: cells are square based on short edge
    let segments = GridLineColorResolver.normalizedSegments(
        config: config, imageSize: CGSize(width: 200, height: 100))
    #expect(!segments.isEmpty)
    // Should have more columns than rows since width > height
}
