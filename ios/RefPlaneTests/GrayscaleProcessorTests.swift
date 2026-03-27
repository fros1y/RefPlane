import UIKit
import Testing
@testable import Underpaint

// MARK: - GrayscaleProcessor
//
// MetalContext.shared may or may not be available in the test environment.
// Both the GPU and CPU paths implement the same Rec-709 linearized luminance
// formula, so the same output invariants hold for either.

@Test
func grayscaleProcessBlackImageStaysBlack() {
    let image = TestImageFactory.makeSolid(width: 8, height: 8, color: .black)
    guard let result = GrayscaleProcessor.process(image: image) else {
        Issue.record("GrayscaleProcessor.process returned nil for a black image")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    // All RGB channels should be 0 (or very close) for a black input
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i]     <= 2)  // R
        #expect(pixels[i + 1] <= 2)  // G
        #expect(pixels[i + 2] <= 2)  // B
    }
}

@Test
func grayscaleProcessWhiteImageStaysWhite() {
    let image = TestImageFactory.makeSolid(width: 8, height: 8, color: .white)
    guard let result = GrayscaleProcessor.process(image: image) else {
        Issue.record("GrayscaleProcessor.process returned nil for a white image")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    // All RGB channels should be 255 (or very close) for a white input
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i]     >= 253)  // R
        #expect(pixels[i + 1] >= 253)  // G
        #expect(pixels[i + 2] >= 253)  // B
    }
}

@Test
func grayscaleProcessPureGrayIsUnchanged() {
    // For a gray input (R=G=B), the Rec-709 luminance equals the channel value,
    // so linearize(r) == luminance and delinearize(luminance) == r. The output
    // gray should round-trip to the same value within ±1.
    let gray128 = UIColor(red: 128.0/255.0, green: 128.0/255.0, blue: 128.0/255.0, alpha: 1.0)
    let image = TestImageFactory.makeSolid(width: 4, height: 4, color: gray128)
    guard let result = GrayscaleProcessor.process(image: image) else {
        Issue.record("GrayscaleProcessor.process returned nil for a gray image")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(abs(Int(pixels[i])     - 128) <= 2)
        #expect(abs(Int(pixels[i + 1]) - 128) <= 2)
        #expect(abs(Int(pixels[i + 2]) - 128) <= 2)
    }
}

@Test
func grayscaleProcessColorImageProducesEqualChannels() {
    // Any color input must produce a grayscale output (R == G == B per pixel).
    let image = TestImageFactory.makeSolid(width: 6, height: 6, color: .red)
    guard let result = GrayscaleProcessor.process(image: image) else {
        Issue.record("GrayscaleProcessor.process returned nil for a red image")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i] == pixels[i + 1])  // R == G
        #expect(pixels[i] == pixels[i + 2])  // R == B
    }
}

@Test
func grayscaleProcessReturnsNilForEmptyImage() {
    let result = GrayscaleProcessor.process(image: UIImage())
    #expect(result == nil)
}
