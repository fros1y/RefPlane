import UIKit
import Testing
@testable import Underpaint

@MainActor
@Test
func resetSimplifyCancelsInflightSimplifyTask() async throws {
    let simplifier = SimplifyOperationProbe()
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [])
        },
        simplifyOperation: { image, downscale, method, onProgress in
            try await simplifier.simplify(
                image: image,
                downscale: downscale,
                method: method,
                onProgress: onProgress
            )
        }
    )

    state.sourceImage = TestImageFactory.makeSolid(width: 40, height: 40, color: .red)
    state.simplifyEnabled = true

    state.applySimplify()
    state.resetSimplify()

    await simplifier.resume(with: TestImageFactory.makeSolid(width: 20, height: 20, color: .blue))
    await Task.yield()
    await Task.yield()

    #expect(state.simplifiedImage == nil)
    #expect(state.processingLabel == "Processing…")
}

@MainActor
@Test
func selectingIsolatedBandChangesDisplayedImage() async throws {
    let processedImage = TestImageFactory.makeSplitColors(
        pixels: [
            (255, 0, 0),
            (0, 0, 255),
        ],
        width: 2,
        height: 1
    )

    let state = AppState(
        processOperation: { _, _, _, _, _ in
            ProcessingResult(
                image: processedImage,
                palette: [],
                paletteBands: [0, 1],
                pixelBands: [0, 1]
            )
        }
    )

    state.sourceImage = processedImage
    state.activeMode = .color
    state.triggerProcessing()
    await Task.yield()
    await Task.yield()

    state.toggleIsolatedBand(1)

    let pixels = state.currentDisplayImage?.toPixelData()?.data
    #expect(pixels != nil)
    #expect(pixels?[0] == 255)
    #expect(pixels?[1] == 255)
    #expect(pixels?[2] == 255)
    #expect(pixels?[4] == 0)
    #expect(pixels?[5] == 0)
    #expect(pixels?[6] == 255)
}

private actor SimplifyOperationProbe {
    private var continuation: CheckedContinuation<UIImage, Error>?

    func simplify(
        image: UIImage,
        downscale: CGFloat,
        method: SimplificationMethod,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with image: UIImage) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}
