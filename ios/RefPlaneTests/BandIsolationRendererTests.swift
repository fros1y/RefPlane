import Testing
@testable import Underpaint

@Test
func bandIsolationWhitesOutNonSelectedPixels() {
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
    #expect(pixels?[0] == 255)
    #expect(pixels?[1] == 255)
    #expect(pixels?[2] == 255)
    #expect(pixels?[4] == 0)
    #expect(pixels?[5] == 0)
    #expect(pixels?[6] == 255)
}
