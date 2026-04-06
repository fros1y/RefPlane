import UIKit
import Testing
@testable import Underpaint

private let transformPresetStoreKey = "AppState.transformPresetStore.v1"

private func clearTransformPresetStore() {
    UserDefaults.standard.removeObject(forKey: transformPresetStoreKey)
}

@MainActor
@Test
func saveCurrentTransformPresetAddsPresetAndSelectsIt() throws {
    clearTransformPresetStore()
    defer { clearTransformPresetStore() }

    let state = AppState()
    state.gridConfig.enabled = true
    state.gridConfig.divisions = 7

    try state.saveCurrentTransformPreset(named: "Studio A")

    #expect(state.savedTransformPresets.count == 1)
    #expect(state.savedTransformPresets[0].name == "Studio A")
    #expect(state.selectedTransformPresetSelection == .saved(state.savedTransformPresets[0].id))
}

@MainActor
@Test
func previousSettingsOptionHiddenWhenSnapshotMatchesSavedPreset() throws {
    clearTransformPresetStore()
    defer { clearTransformPresetStore() }

    let state = AppState()

    try state.saveCurrentTransformPreset(named: "Balanced")
    state.selectTransformPreset(.saved(state.savedTransformPresets[0].id))

    #expect(state.shouldShowPreviousSettingsOption == false)
    #expect(state.availableTransformPresetSelections.contains(.saved(state.savedTransformPresets[0].id)))
    #expect(!state.availableTransformPresetSelections.contains(.previous))
}

@MainActor
@Test
func selectingDefaultPresetRestoresDefaultTransformationValues() {
    clearTransformPresetStore()
    defer { clearTransformPresetStore() }

    let state = AppState()

    state.abstractionStrength = 0.9
    state.gridConfig.enabled = true
    state.gridConfig.divisions = 9
    state.valueConfig.levels = 5
    state.colorConfig.paletteSpread = 0
    state.depthConfig.enabled = true

    state.selectTransformPreset(.appDefault)

    #expect(state.abstractionStrength == 0.5)
    #expect(state.gridConfig.enabled == false)
    #expect(state.gridConfig.divisions == 4)
    #expect(state.valueConfig.levels == 3)
    #expect(state.colorConfig.paletteSpread == 1)
    #expect(state.depthConfig.enabled == false)
}

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
func selectingFocusedBandChangesDisplayedImage() async throws {
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

    state.toggleFocusedBand(1)

    let pixels = state.currentDisplayImage?.toPixelData()?.data
    #expect(pixels != nil)
    // Non-selected pixel (red) should be desaturated and dimmed — much darker than original
    #expect(pixels![0] < 100)
    #expect(pixels![1] < 100)
    #expect(pixels![2] < 100)
    // Selected band pixel (blue) should remain unchanged
    #expect(pixels?[4] == 0)
    #expect(pixels?[5] == 0)
    #expect(pixels?[6] == 255)
}

@MainActor
@Test
func selectingMultipleFocusedBandsSubduesOnlyUnfocusedPixels() async throws {
    let processedImage = TestImageFactory.makeSplitColors(
        pixels: [
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255),
        ],
        width: 3,
        height: 1
    )

    let state = AppState(
        processOperation: { _, _, _, _, _ in
            ProcessingResult(
                image: processedImage,
                palette: [],
                paletteBands: [0, 1, 2],
                pixelBands: [0, 1, 2],
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

    state.toggleFocusedBand(0)
    state.toggleFocusedBand(2)

    #expect(state.focusedBands == Set([0, 2]))

    let pixels = state.currentDisplayImage?.toPixelData()?.data
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

@MainActor
@Test
func processingResultsClearFocusedBands() async throws {
    let firstImage = TestImageFactory.makeSplitColors(
        pixels: [
            (255, 0, 0),
            (0, 0, 255),
        ],
        width: 2,
        height: 1
    )
    let secondImage = TestImageFactory.makeSplitColors(
        pixels: [
            (0, 255, 0),
            (255, 255, 255),
        ],
        width: 2,
        height: 1
    )

    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(
                image: image,
                palette: [],
                paletteBands: [0, 1],
                pixelBands: [0, 1],
                pigmentRecipes: nil,
                selectedTubes: [],
                clippedRecipeIndices: []
            )
        }
    )

    state.sourceImage = firstImage
    state.activeMode = .color
    state.triggerProcessing()
    for _ in 0..<50 where state.isProcessing { await Task.yield() }

    state.toggleFocusedBand(1)
    #expect(state.focusedBands == Set([1]))

    state.sourceImage = secondImage
    state.triggerProcessing()
    for _ in 0..<50 where state.isProcessing { await Task.yield() }

    #expect(state.focusedBands.isEmpty)
    let pixels = state.currentDisplayImage?.toPixelData()?.data
    #expect(pixels?[0] == 0)
    #expect(pixels?[1] == 255)
    #expect(pixels?[2] == 0)
}

@Test
func canvasBandTapTrackerShowsBubbleOnFirstTapAndFocusesOnSecondQuickSameBandTap() {
    var tracker = CanvasBandTapTracker(repeatWindow: 0.45)

    #expect(tracker.action(for: 2, at: 10.0) == .inspect(2))
    #expect(tracker.action(for: 2, at: 10.2) == .focus(2))
}

@Test
func canvasBandTapTrackerTreatsSlowRepeatAsAnotherInspect() {
    var tracker = CanvasBandTapTracker(repeatWindow: 0.45)

    #expect(tracker.action(for: 2, at: 10.0) == .inspect(2))
    #expect(tracker.action(for: 2, at: 10.7) == .inspect(2))
}

@Test
func canvasBandTapTrackerReplacesPendingBandWhenTappingDifferentBand() {
    var tracker = CanvasBandTapTracker(repeatWindow: 0.45)

    #expect(tracker.action(for: 1, at: 10.0) == .inspect(1))
    #expect(tracker.action(for: 3, at: 10.2) == .inspect(3))
    #expect(tracker.action(for: 3, at: 10.35) == .focus(3))
}

@Test
func canvasBandTapTrackerResetsViewportOnSecondQuickEmptyCanvasTap() {
    var tracker = CanvasBandTapTracker(repeatWindow: 0.45)

    #expect(tracker.action(for: nil, at: 10.0) == .inspect(nil))
    #expect(tracker.action(for: nil, at: 10.2) == .resetViewport)
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
    state.focusedBands = [0]
    state.activeMode = .value

    state.setMode(.tonal)

    #expect(state.activeMode == .tonal)
    #expect(state.processedImage == nil)
    #expect(state.paletteColors.isEmpty)
    #expect(state.paletteBands.isEmpty)
    #expect(state.focusedBands.isEmpty)
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

    state.toggleFocusedBand(1)

    #expect(state.compareAfterImage === state.currentDisplayImage)
}

// MARK: - isSimplifying

@MainActor
@Test
func isSimplifyingIsTrueDuringAbstractionAndFalseAfter() async throws {
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

    state.sourceImage         = TestImageFactory.makeSolid(width: 40, height: 40, color: .red)
    state.abstractionStrength  = 0.5

    state.applyAbstraction()

    // isSimplifying should be true while the abstraction task is running
    #expect(state.isSimplifying == true)

    let result = TestImageFactory.makeSolid(width: 20, height: 20, color: .blue)
    // Yield to let the Task start and reach the continuation
    for _ in 0..<50 {
        await Task.yield()
        if await abstractor.hasContinuation { break }
    }
    await abstractor.resume(with: result)
    // Allow the MainActor continuation to run
    for _ in 0..<50 where state.isSimplifying { await Task.yield() }

    // isSimplifying should be cleared once abstraction completes
    #expect(state.isSimplifying == false)
}

@MainActor
@Test
func resetAbstractionClearsAbstractedImage() {
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        }
    )

    state.sourceImage = TestImageFactory.makeSolid(width: 10, height: 10, color: .red)
    state.abstractedImage = TestImageFactory.makeSolid(width: 10, height: 10, color: .blue)

    state.resetAbstraction()

    #expect(state.abstractedImage == nil)
}

@MainActor
@Test
func isSimplifyingIsFalseAfterResetAbstraction() {
    let state = AppState(
        processOperation: { image, _, _, _, _ in
            ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])
        }
    )

    state.sourceImage = TestImageFactory.makeSolid(width: 40, height: 40, color: .red)
    state.abstractionStrength = 0.5
    state.applyAbstraction()
    #expect(state.isSimplifying == true)

    state.resetAbstraction()

    #expect(state.isSimplifying == false)
}

@MainActor
@Test
func computeDepthMapUsesEmbeddedDepthAndSkipsML() async throws {
    var mlWasCalled = false
    let state = AppState(depthMapOperation: { _ in
        mlWasCalled = true
        throw DepthEstimatorError.modelUnavailable
    })

    let baseImage = TestImageFactory.makeSolid(width: 100, height: 100, color: .gray)
    let fakeDepth = TestImageFactory.makeHorizontalDepthRamp(width: 50, height: 50)

    state.loadImage(ImportedImagePayload(image: baseImage, embeddedDepthMap: fakeDepth))
    state.depthConfig.enabled = true
    state.computeDepthMap()

    try await Task.sleep(for: .milliseconds(200))

    #expect(mlWasCalled == false)
    #expect(state.depthSource == .embedded)
    #expect(state.depthMap != nil)
    #expect(state.depthMap?.cgImage?.width == 100)
    #expect(state.depthMap?.cgImage?.height == 100)
}

@MainActor
@Test
func loadImageClearsDepthSourceAndEmbeddedMap() {
    let state = AppState()
    let fakeDepth = TestImageFactory.makeHorizontalDepthRamp(width: 50, height: 50)

    state.loadImage(
        ImportedImagePayload(
            image: TestImageFactory.makeSolid(width: 100, height: 100, color: .gray),
            embeddedDepthMap: fakeDepth
        )
    )
    state.depthSource = .embedded

    state.loadImage(TestImageFactory.makeSolid(width: 100, height: 100, color: .red))

    #expect(state.embeddedDepthMap == nil)
    #expect(state.depthSource == nil)
}

@MainActor
@Test
func legacyKuwaharaPresetFallsBackToBalancedAbstraction() throws {
    clearTransformPresetStore()
    defer { clearTransformPresetStore() }

    let payload = """
    {
      "previousSnapshot" : {
        "abstractionMethod" : "Kuwahara",
        "abstractionStrength" : 0.5,
        "activeMode" : "original",
        "backgroundCutoff" : 0.66,
        "backgroundMode" : "No",
        "colorLimit" : 24,
        "colorQuantizationBias" : 0,
        "contourCustomColor" : {
          "alpha" : 1,
          "blue" : 1,
          "green" : 1,
          "red" : 1
        },
        "contourEnabled" : false,
        "contourLevels" : 5,
        "contourLineStyle" : "Auto",
        "contourOpacity" : 0.7,
        "depthEffectIntensity" : 0.5,
        "depthEnabled" : false,
        "enabledPigmentIDs" : [],
        "foregroundCutoff" : 0.33,
        "grayscaleConversion" : "None",
        "gridCustomColor" : {
          "alpha" : 1,
          "blue" : 1,
          "green" : 1,
          "red" : 1
        },
        "gridDivisions" : 4,
        "gridEnabled" : false,
        "gridLineStyle" : "Auto",
        "gridOpacity" : 0.7,
        "gridShowDiagonals" : false,
        "kuwaharaStrength" : 0.5,
        "maxPigmentsPerMix" : 3,
        "minConcentration" : 0.02,
        "paletteSelectionEnabled" : false,
        "paletteSpread" : 0,
        "valueDistribution" : "Even",
        "valueLevels" : 3,
        "valueQuantizationBias" : 0,
        "valueThresholds" : [
          0.3333333333333333,
          0.6666666666666666
        ]
      },
      "savedPresets" : [],
      "schemaVersion" : 1
    }
    """

    UserDefaults.standard.set(Data(payload.utf8), forKey: transformPresetStoreKey)

    let state = AppState()

    #expect(state.previousTransformSnapshot?.abstractionMethod == .apisr)
    #expect(state.abstractionMethod == .apisr)
}

// MARK: -

private actor AbstractionOperationProbe {
    private var continuation: CheckedContinuation<UIImage, Error>?

    var hasContinuation: Bool { continuation != nil }

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
