import SwiftUI
import Testing
@testable import Underpaint

private let autoContrastConfig = GridConfig(
    enabled: true,
    divisions: 4,
    cellAspect: .matchImage,
    showDiagonals: false,
    showCenterLines: false,
    lineStyle: .autoContrast,
    customColor: .white,
    opacity: 0.7
)

@Test
func autoContrastChoosesTheHigherContrastTone() {
    for percentage in 0...100 {
        let luminance = Double(percentage) / 100.0
        let tone = GridLineColorResolver.autoContrastTone(forAverageLuminance: luminance)
        let blackContrast = GridLineColorResolver.contrastDistance(from: luminance, to: .black)
        let whiteContrast = GridLineColorResolver.contrastDistance(from: luminance, to: .white)

        switch tone {
        case .black:
            #expect(blackContrast >= whiteContrast)
        case .white:
            #expect(whiteContrast >= blackContrast)
        }
    }
}

@Test
func autoContrastDefaultsToWhiteWithoutImageData() {
    #expect(GridLineColorResolver.autoContrastTone(forAverageLuminance: nil) == .white)
}

@Test
func autoContrastAdaptsAcrossSplitBackgrounds() {
    let image = TestImageFactory.makeSplitColors(
        pixels: [
            (255, 255, 255),
            (255, 255, 255),
            (0, 0, 0),
            (0, 0, 0),
        ],
        width: 4,
        height: 1
    )
    let line = GridLineSegment(
        start: CGPoint(x: 0, y: 0.5),
        end: CGPoint(x: 1, y: 0.5)
    )

    let resolved = GridLineColorResolver.resolvedSegments(
        config: autoContrastConfig,
        image: image,
        segments: [line]
    )

    let tones = resolved.compactMap(\.tone)
    #expect(tones.count >= 2)
    #expect(tones.first == .black)
    #expect(tones.last == .white)
}

@Test
func normalizedSegmentsIncludeTrailingBorderForSquareCells() {
    let config = GridConfig(
        enabled: true,
        divisions: 4,
        cellAspect: .square,
        showDiagonals: false,
        showCenterLines: false,
        lineStyle: .autoContrast,
        customColor: .white,
        opacity: 0.7
    )

    let segments = GridLineColorResolver.normalizedSegments(
        config: config,
        imageSize: CGSize(width: 100, height: 60)
    )

    #expect(segments.contains {
        $0.start == CGPoint(x: 1, y: 0) && $0.end == CGPoint(x: 1, y: 1)
    })
}
