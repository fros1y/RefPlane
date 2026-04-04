import UIKit
import Testing
@testable import Underpaint

// MARK: - Anisotropic Kuwahara filter tests
//
// These tests exercise MetalContext.anisotropicKuwahara directly.
// If MetalContext.shared is nil in the test environment (no GPU), every
// test is skipped via an early return so the suite still passes on CI.

// MARK: - Uniform-image invariants

@Test
func kuwaharaUniformBlackImageIsUnchanged() {
    guard let ctx = MetalContext.shared else { return }
    let image = TestImageFactory.makeSolid(width: 16, height: 16, color: .black)
    guard let cg = image.cgImage else { return }
    guard let result = ctx.anisotropicKuwahara(cg, radius: 4) else {
        Issue.record("anisotropicKuwahara returned nil for a black image")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i]     <= 2, "R channel should remain near 0 for uniform black input")
        #expect(pixels[i + 1] <= 2, "G channel should remain near 0 for uniform black input")
        #expect(pixels[i + 2] <= 2, "B channel should remain near 0 for uniform black input")
    }
}

@Test
func kuwaharaUniformWhiteImageIsUnchanged() {
    guard let ctx = MetalContext.shared else { return }
    let image = TestImageFactory.makeSolid(width: 16, height: 16, color: .white)
    guard let cg = image.cgImage else { return }
    guard let result = ctx.anisotropicKuwahara(cg, radius: 4) else {
        Issue.record("anisotropicKuwahara returned nil for a white image")
        return
    }
    guard let (pixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        #expect(pixels[i]     >= 253, "R channel should remain near 255 for uniform white input")
        #expect(pixels[i + 1] >= 253, "G channel should remain near 255 for uniform white input")
        #expect(pixels[i + 2] >= 253, "B channel should remain near 255 for uniform white input")
    }
}

// MARK: - Non-trivial image is actually modified

/// A fine 1-pixel checkerboard (alternating black/white at every pixel) produces
/// zero Sobel gradients — the structure tensor is isotropic (A ≈ 0) — so the
/// ellipse is circular and every sector samples many pixels. With a radius-4
/// filter the output must blend those neighbouring pixels, producing grey tones
/// rather than the original 0/255 values.  This verifies the filter is running
/// and changing pixel values for a non-trivial input.
@Test
func kuwaharaModifiesCheckerboardImage() {
    guard let ctx = MetalContext.shared else { return }

    let size = 20
    var pixelData: [(UInt8, UInt8, UInt8)] = []
    pixelData.reserveCapacity(size * size)
    for y in 0..<size {
        for x in 0..<size {
            let value: UInt8 = ((x + y) % 2 == 0) ? 255 : 0
            pixelData.append((value, value, value))
        }
    }
    let image = TestImageFactory.makeSplitColors(pixels: pixelData, width: size, height: size)
    guard let cg = image.cgImage else { return }

    guard let result = ctx.anisotropicKuwahara(cg, radius: 4) else {
        Issue.record("anisotropicKuwahara returned nil for a checkerboard image")
        return
    }

    guard let (inputPixels,  _, _) = image.toPixelData(),
          let (outputPixels, _, _) = result.toPixelData() else {
        Issue.record("toPixelData returned nil")
        return
    }

    // At least one pixel must differ between input and output.
    // For a fine checkerboard the filter blends neighbouring pixels and the
    // output can never be identical to an alternating 0/255 pattern.
    var changed = false
    for i in stride(from: 0, to: min(inputPixels.count, outputPixels.count), by: 4) {
        if inputPixels[i] != outputPixels[i]
            || inputPixels[i + 1] != outputPixels[i + 1]
            || inputPixels[i + 2] != outputPixels[i + 2] {
            changed = true
            break
        }
    }
    #expect(changed,
            "Kuwahara filter produced output identical to input for a checkerboard — filter is not modifying pixels")
}
