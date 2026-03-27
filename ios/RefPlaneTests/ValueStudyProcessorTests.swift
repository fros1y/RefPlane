import UIKit
import Testing
@testable import Underpaint

// MARK: - ValueStudyProcessor
//
// Both the GPU and CPU paths implement the same quantization formula, so the
// same invariants hold for either execution path.

private func makeConfig(levels: Int, thresholds: [Double], minRegionSize: MinRegionSize = .off) -> ValueConfig {
    ValueConfig(levels: levels, thresholds: thresholds, minRegionSize: minRegionSize)
}

@Test
func valueStudySolidBlackAssignedToLowestLevel() {
    let image = TestImageFactory.makeSolid(width: 8, height: 8, color: .black)
    let config = makeConfig(levels: 2, thresholds: [0.5])
    guard let result = ValueStudyProcessor.process(image: image, config: config) else {
        Issue.record("ValueStudyProcessor.process returned nil for black image")
        return
    }
    #expect(result.pixelBands.allSatisfy { $0 == 0 })
}

@Test
func valueStudySolidWhiteAssignedToHighestLevel() {
    let image = TestImageFactory.makeSolid(width: 8, height: 8, color: .white)
    let config = makeConfig(levels: 2, thresholds: [0.5])
    guard let result = ValueStudyProcessor.process(image: image, config: config) else {
        Issue.record("ValueStudyProcessor.process returned nil for white image")
        return
    }
    #expect(result.pixelBands.allSatisfy { $0 == 1 })
}

@Test
func valueStudyLevelColorsCountMatchesLevels() {
    let image = TestImageFactory.makeSolid(width: 4, height: 4, color: .gray)
    for levels in 2...5 {
        let config = makeConfig(levels: levels, thresholds: defaultThresholds(for: levels))
        guard let result = ValueStudyProcessor.process(image: image, config: config) else {
            Issue.record("ValueStudyProcessor.process returned nil for levels=\(levels)")
            continue
        }
        #expect(result.levelColors.count == levels)
    }
}

@Test
func valueStudyPixelBandsCountMatchesPixelCount() {
    let width = 10
    let height = 10
    let image = TestImageFactory.makeSolid(width: width, height: height, color: .gray)
    let config = makeConfig(levels: 3, thresholds: defaultThresholds(for: 3))
    guard let result = ValueStudyProcessor.process(image: image, config: config) else {
        Issue.record("ValueStudyProcessor.process returned nil")
        return
    }
    #expect(result.pixelBands.count == width * height)
}

@Test
func valueStudyPixelBandsAreValidLevelIndices() {
    let image = TestImageFactory.makeSolid(width: 6, height: 6, color: .gray)
    let levels = 4
    let config = makeConfig(levels: levels, thresholds: defaultThresholds(for: levels))
    guard let result = ValueStudyProcessor.process(image: image, config: config) else {
        Issue.record("ValueStudyProcessor.process returned nil")
        return
    }
    #expect(result.pixelBands.allSatisfy { $0 >= 0 && $0 < levels })
}

@Test
func valueStudyTwoToneImageSeparatesIntoBands() {
    // One black pixel → level 0, one white pixel → level 1.
    // The 2-pixel image is too small for region cleanup to trigger (minPixels=0).
    let image = TestImageFactory.makeSplitColors(
        pixels: [(0, 0, 0), (255, 255, 255)],
        width: 2,
        height: 1
    )
    let config = makeConfig(levels: 2, thresholds: [0.5])
    guard let result = ValueStudyProcessor.process(image: image, config: config) else {
        Issue.record("ValueStudyProcessor.process returned nil for two-tone image")
        return
    }
    #expect(result.pixelBands.count == 2)
    #expect(result.pixelBands[0] == 0)  // black → lowest level
    #expect(result.pixelBands[1] == 1)  // white → highest level
}

@Test
func valueStudyRegionCleanupMergesIsolatedPixel() {
    // 200-pixel wide, 1-pixel tall image: 199 black pixels + 1 white pixel at the end.
    // With minRegionSize=.large (factor=0.01): minPixels=Int(200*0.01)=2.
    // The isolated white pixel (size 1) < 2 and gets merged to the dominant neighbor (black).
    var pixels = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 200)
    pixels[199] = (255, 255, 255)
    let image = TestImageFactory.makeSplitColors(pixels: pixels, width: 200, height: 1)
    let config = makeConfig(levels: 2, thresholds: [0.5], minRegionSize: .large)
    guard let result = ValueStudyProcessor.process(image: image, config: config) else {
        Issue.record("ValueStudyProcessor.process returned nil")
        return
    }
    #expect(result.pixelBands.allSatisfy { $0 == 0 },
            "All pixels should be level 0 after the isolated white pixel is cleaned")
}

@Test
func valueStudyReturnsNilForEmptyImage() {
    let config = makeConfig(levels: 2, thresholds: [0.5])
    let result = ValueStudyProcessor.process(image: UIImage(), config: config)
    #expect(result == nil)
}
