import UIKit
import Testing
@testable import Underpaint

// MARK: - BandIsolationRenderer extended tests

@Test
func isolateReturnsNilForEmptyImage() {
    let result = BandIsolationRenderer.isolate(
        image: UIImage(),
        pixelBands: [],
        selectedBand: 0
    )
    #expect(result == nil)
}

@Test
func isolateReturnsNilForMismatchedBands() {
    let image = TestImageFactory.makeSolid(width: 5, height: 5, color: .red)
    // Provide wrong number of bands
    let result = BandIsolationRenderer.isolate(
        image: image,
        pixelBands: [0, 1], // only 2, but image is 5x5 = 25 pixels
        selectedBand: 0
    )
    #expect(result == nil)
}

@Test
func isolateProducesImageWithCorrectDimensions() {
    let w = 10
    let h = 8
    let image = TestImageFactory.makeSolid(width: w, height: h, color: .blue)
    let bands = [Int](repeating: 0, count: w * h)
    let result = BandIsolationRenderer.isolate(
        image: image,
        pixelBands: bands,
        selectedBand: 0
    )
    #expect(result != nil)
    if let cg = result?.cgImage {
        #expect(cg.width == w)
        #expect(cg.height == h)
    }
}

@Test
func isolateSelectedBandRetainsOriginalColors() {
    let image = TestImageFactory.makeSolid(width: 4, height: 4, color: .red)
    // All pixels are in band 0
    let bands = [Int](repeating: 0, count: 16)
    let result = BandIsolationRenderer.isolate(
        image: image,
        pixelBands: bands,
        selectedBand: 0
    )
    #expect(result != nil)
    // Since all pixels are the selected band, output should match input closely
    if let (srcPixels, _, _) = image.toPixelData(),
       let (resPixels, _, _) = result?.toPixelData() {
        for i in stride(from: 0, to: min(srcPixels.count, resPixels.count), by: 4) {
            #expect(abs(Int(srcPixels[i]) - Int(resPixels[i])) <= 1)
            #expect(abs(Int(srcPixels[i+1]) - Int(resPixels[i+1])) <= 1)
            #expect(abs(Int(srcPixels[i+2]) - Int(resPixels[i+2])) <= 1)
        }
    }
}

@Test
func isolateNonSelectedBandIsDimmed() {
    let image = TestImageFactory.makeSolid(width: 4, height: 4, color: .red)
    // All pixels in band 1, but we isolate band 0
    let bands = [Int](repeating: 1, count: 16)
    let result = BandIsolationRenderer.isolate(
        image: image,
        pixelBands: bands,
        selectedBand: 0
    )
    #expect(result != nil)
    // All pixels should be dimmed/desaturated
    if let (resPixels, _, _) = result?.toPixelData() {
        // Red channel should be lower than the original 255 due to dimming
        #expect(resPixels[0] < 255)
    }
}

@Test
func isolateWithCustomDesaturationAndDimming() {
    let image = TestImageFactory.makeSolid(width: 5, height: 5, color: .green)
    let bands = [Int](repeating: 1, count: 25)
    let result = BandIsolationRenderer.isolate(
        image: image,
        pixelBands: bands,
        selectedBand: 0,
        desaturation: 1.0,
        dimming: 0.0
    )
    #expect(result != nil)
}

@Test
func isolateWithMixedBands() {
    // Create an image with two bands
    let image = TestImageFactory.makeSolid(width: 4, height: 2, color: .yellow)
    // First row: band 0, second row: band 1
    let bands = [0, 0, 0, 0, 1, 1, 1, 1]
    let result = BandIsolationRenderer.isolate(
        image: image,
        pixelBands: bands,
        selectedBand: 0
    )
    #expect(result != nil)
}
