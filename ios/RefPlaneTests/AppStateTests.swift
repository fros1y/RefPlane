import UIKit
import Testing
@testable import Underpaint

@MainActor
@Test
func resetAbstractionCancelsInflightAbstractionTask() async throws {
    let abstractor = AbstractionOperationProbe()
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        },
        abstractionOperation: { image, downscale, method, onProgress in
            try await abstractor.abstract(
                image: image,
                downscale: downscale,
                method: method,
                onProgress: onProgress
            )
        }
    )

    state.sourceImage = TestImageFactory.makeSolid(width: 40, height: 40, color: .red)

    state.applyAbstraction()
    state.resetAbstraction()

    await abstractor.resume(with: TestImageFactory.makeSolid(width: 20, height: 20, color: .blue))
    await Task.yield()
    await Task.yield()

    #expect(state.abstractedImage == nil)
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
                pixelBands: [0, 1],
                pigmentRecipes: nil,
                selectedTubes: [],
                clippedRecipeIndices: []
            )
        }
    )

    state.sourceImage = processedImage
    state.activeMode = .color
    state.triggerProcessing()
    for _ in 0..<50 where state.isProcessing { await Task.yield() }

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

// MARK: - Additional AppState coverage

@MainActor
@Test
func setModeClearsProcessedState() {
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        }
    )
    let img = TestImageFactory.makeSolid(width: 4, height: 4, color: .red)
    state.processedImage = img
    state.paletteColors = [.red]
    state.paletteBands = [0]
    state.isolatedBand = 0
    state.activeMode = .value

    state.setMode(.tonal)

    #expect(state.activeMode == .tonal)
    #expect(state.processedImage == nil)
    #expect(state.paletteColors.isEmpty)
    #expect(state.paletteBands.isEmpty)
    #expect(state.isolatedBand == nil)
}

@MainActor
@Test
func setModeToSameModeIsNoOp() {
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        }
    )
    let img = TestImageFactory.makeSolid(width: 4, height: 4, color: .red)
    state.processedImage = img
    state.paletteColors = [.red]
    state.activeMode = .value

    state.setMode(.value)  // same mode — guard returns early

    #expect(state.processedImage === img)
    #expect(!state.paletteColors.isEmpty)
}

@MainActor
@Test
func displayBaseImagePrefersAbstractedOverSource() {
    let state = AppState()
    let source     = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let abstracted = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)

    state.sourceImage    = source
    state.abstractedImage = abstracted

    #expect(state.displayBaseImage === abstracted)
}

@MainActor
@Test
func displayBaseImageFallsBackToSourceWhenNoAbstracted() {
    let state = AppState()
    let source = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)

    state.sourceImage    = source
    state.abstractedImage = nil

    #expect(state.displayBaseImage === source)
}

@MainActor
@Test
func currentDisplayImageShowsBaseImageInOriginalMode() {
    let state = AppState()
    let source    = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let processed = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)

    state.sourceImage    = source
    state.processedImage = processed
    state.activeMode     = .original

    #expect(state.currentDisplayImage === source)
}

@MainActor
@Test
func compareAfterImageUsesCurrentDisplayImageInProcessedModes() async throws {
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
                pixelBands: [0, 1],
                pigmentRecipes: nil,
                selectedTubes: [],
                clippedRecipeIndices: []
            )
        }
    )

    state.sourceImage = processedImage
    state.activeMode = .color
    state.triggerProcessing()
    for _ in 0..<50 where state.isProcessing { await Task.yield() }

    #expect(state.compareAfterImage === state.currentDisplayImage)

    state.toggleIsolatedBand(1)

    #expect(state.compareAfterImage === state.currentDisplayImage)
}

// MARK: - Kuwahara tests

@MainActor
@Test
func kuwaharaStrengthDefaultsToZero() {
    let state = AppState()
    #expect(state.kuwaharaStrength == 0)
}

@MainActor
@Test
func displayBaseImagePrefersKuwaharaFilteredOverAbstracted() {
    let state = AppState()
    let source     = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let abstracted = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)
    let filtered   = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)

    state.sourceImage         = source
    state.abstractedImage     = abstracted
    state.kuwaharaFilteredImage = filtered

    #expect(state.displayBaseImage === filtered)
}

@MainActor
@Test
func displayBaseImageFallsBackToAbstractedWhenNoKuwahara() {
    let state = AppState()
    let source     = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let abstracted = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)

    state.sourceImage         = source
    state.abstractedImage     = abstracted
    state.kuwaharaFilteredImage = nil

    #expect(state.displayBaseImage === abstracted)
}

@MainActor
@Test
func applyKuwaharaWithZeroStrengthClearsFilteredImageAndTriggersProcessing() async throws {
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        }
    )
    let source   = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let filtered = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)

    state.sourceImage           = source
    state.kuwaharaFilteredImage = filtered
    state.kuwaharaStrength      = 0

    state.applyKuwahara()

    #expect(state.kuwaharaFilteredImage == nil)
}

@MainActor
@Test
func applyKuwaharaCallsOperationAndStoresResult() async throws {
    let expectedImage = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)
    let kuwaharaProbe = KuwaharaOperationProbe(result: expectedImage)

    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        },
        kuwaharaOperation: { image, radius in
            await kuwaharaProbe.filter(image: image, radius: radius)
        }
    )

    let source = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    state.sourceImage      = source
    state.kuwaharaStrength = 0.5  // radius = Int(0.5 * 8) = 4

    state.applyKuwahara()
    for _ in 0..<50 where state.isProcessing { await Task.yield() }

    let callCount = await kuwaharaProbe.callCount
    let lastRadius = await kuwaharaProbe.lastRadius
    #expect(callCount == 1)
    #expect(lastRadius == 4)
    #expect(state.kuwaharaFilteredImage === expectedImage)
}

@MainActor
@Test
func loadImageResetsKuwaharaFilteredImage() async throws {
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        }
    )

    let filtered = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)
    state.kuwaharaFilteredImage = filtered

    let newImage = TestImageFactory.makeSolid(width: 20, height: 20, color: .blue)
    state.loadImage(newImage)

    #expect(state.kuwaharaFilteredImage == nil)
}

@MainActor
@Test
func abstractionAppliesKuwaharaPostFilter() async throws {
    let abstractedImage = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)
    let filteredImage   = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)

    let abstractor = AbstractionOperationProbe()
    let kuwaharaProbe = KuwaharaOperationProbe(result: filteredImage)

    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        },
        abstractionOperation: { image, downscale, method, onProgress in
            try await abstractor.abstract(image: image, downscale: downscale, method: method, onProgress: onProgress)
        },
        kuwaharaOperation: { image, radius in
            await kuwaharaProbe.filter(image: image, radius: radius)
        }
    )

    let source = TestImageFactory.makeSolid(width: 40, height: 40, color: .red)
    state.sourceImage      = source
    state.kuwaharaStrength = 0.5

    state.applyAbstraction()
    await abstractor.resume(with: abstractedImage)
    for _ in 0..<50 where state.isProcessing { await Task.yield() }

    let callCount = await kuwaharaProbe.callCount
    #expect(callCount == 1)
    #expect(state.abstractedImage === abstractedImage)
    #expect(state.kuwaharaFilteredImage === filteredImage)
    #expect(state.displayBaseImage === filteredImage)
}

@MainActor
@Test
func resetAbstractionClearsKuwaharaFilteredImage() {
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        }
    )

    let source   = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    let filtered = TestImageFactory.makeSolid(width: 10, height: 10, color: .green)

    state.sourceImage           = source
    state.abstractedImage       = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)
    state.kuwaharaFilteredImage = filtered
    state.kuwaharaStrength      = 0  // no Kuwahara after reset

    state.resetAbstraction()

    #expect(state.abstractedImage == nil)
    #expect(state.kuwaharaFilteredImage == nil)
}

// MARK: -

private actor AbstractionOperationProbe {
    private var continuation: CheckedContinuation<UIImage, Error>?

    func abstract(
        image: UIImage,
        downscale: CGFloat,
        method: AbstractionMethod,
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

private actor KuwaharaOperationProbe {
    private let fixedResult: UIImage?
    private(set) var callCount: Int = 0
    private(set) var lastRadius: Int? = nil

    init(result: UIImage?) {
        self.fixedResult = result
    }

    func filter(image: UIImage, radius: Int) -> UIImage? {
        callCount += 1
        lastRadius = radius
        return fixedResult
    }
}
