import Testing
@testable import Underpaint

@Test
func bandIsolationDesaturatesAndDarkenNonSelectedPixels() {
    let source = TestImageFactory.makeSplitColors(
        pixels: [
            (255, 0, 0),
            (0, 0, 255),
        ],
        width: 2,
        height: 1
    )

    let isolated = BandIsolationRenderer.isolate(
        image: source,
        pixelBands: [0, 1],
        selectedBand: 1
    )

    let pixels = isolated?.toPixelData()?.data
    #expect(pixels != nil)

    // Selected band pixel (index 1: blue) should remain unchanged
    #expect(pixels?[4] == 0)
    #expect(pixels?[5] == 0)
    #expect(pixels?[6] == 255)

    // Non-selected pixel (index 0: red 255,0,0) should be desaturated and dimmed.
    // Luma of (255,0,0) ≈ 76.245. With default desaturation=0.85 and dimming=0.45:
    // R = (76.245 * 0.85 + 255 * 0.15) * 0.55 ≈ 56.7 → 57
    // G = (76.245 * 0.85 + 0 * 0.15) * 0.55 ≈ 35.6 → 36
    // B = (76.245 * 0.85 + 0 * 0.15) * 0.55 ≈ 35.6 → 36
    let r = Int(pixels![0])
    let g = Int(pixels![1])
    let b = Int(pixels![2])
    // Should be significantly dimmer than original
    #expect(r < 100)
    #expect(g < 100)
    #expect(b < 100)
    // Should retain some warmth (r > g and r > b due to red input)
    #expect(r > g)
}

@Test
func bandIsolationReturnsNilOnMismatchedBands() {
    let source = TestImageFactory.makeSplitColors(
        pixels: [(128, 128, 128)],
        width: 1,
        height: 1
    )

    let result = BandIsolationRenderer.isolate(
        image: source,
        pixelBands: [0, 1],  // 2 bands for 1 pixel — mismatch
        selectedBand: 0
    )

    #expect(result == nil)
}

@Test
func bandIsolationPreservesAllPixelsWhenAllSelected() {
    let source = TestImageFactory.makeSplitColors(
        pixels: [
            (200, 100, 50),
            (200, 100, 50),
        ],
        width: 2,
        height: 1
    )

    let isolated = BandIsolationRenderer.isolate(
        image: source,
        pixelBands: [0, 0],
        selectedBand: 0
    )

    let pixels = isolated?.toPixelData()?.data
    #expect(pixels != nil)
    // All pixels belong to selected band — should be unchanged
    #expect(pixels?[0] == 200)
    #expect(pixels?[1] == 100)
    #expect(pixels?[2] == 50)
    #expect(pixels?[4] == 200)
    #expect(pixels?[5] == 100)
    #expect(pixels?[6] == 50)
}

@Test
func bandIsolationPreservesMultipleSelectedBands() {
    let source = TestImageFactory.makeSplitColors(
        pixels: [
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255),
        ],
        width: 3,
        height: 1
    )

    let isolated = BandIsolationRenderer.isolate(
        image: source,
        pixelBands: [0, 1, 2],
        selectedBands: Set([0, 2])
    )

    let pixels = isolated?.toPixelData()?.data
    #expect(pixels != nil)
    #expect(pixels?[0] == 255)
    #expect(pixels?[1] == 0)
    #expect(pixels?[2] == 0)
    #expect((pixels?[4] ?? 255) < 120)
    #expect((pixels?[5] ?? 255) < 120)
    #expect((pixels?[6] ?? 255) < 120)
    #expect(pixels?[8] == 0)
    #expect(pixels?[9] == 0)
    #expect(pixels?[10] == 255)
}
