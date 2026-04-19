import Observation
import SwiftUI
import os

@Observable
@MainActor
class AppState {
    @ObservationIgnored
    static let depthLogger = Logger(
        subsystem: AppInstrumentation.subsystem,
        category: "DepthPipeline"
    )

    @ObservationIgnored
    static let modeLogger = Logger(
        subsystem: AppInstrumentation.subsystem,
        category: "ModeSelection"
    )

    typealias ProcessOperation = @Sendable (
        UIImage,
        RefPlaneMode,
        ValueConfig,
        ColorConfig,
        @escaping @Sendable (Double) -> Void
    ) async throws -> ProcessingResult

    typealias AbstractionOperation = @Sendable (
        UIImage,
        CGFloat,
        AbstractionMethod,
        @escaping @Sendable (Double) -> Void
    ) async throws -> UIImage

    typealias DepthMapOperation = @Sendable (UIImage) async throws -> UIImage
    typealias DepthEffectOperation = @Sendable (UIImage, UIImage, DepthConfig) -> UIImage?

    let transform = TransformState()
    let depth = DepthState()
    let pipeline = PipelineState()
    let processing = ProcessingCoordinator()
    let sessionStore: SessionStore
    let customPaletteStore: CustomPaletteStore

    var fullResolutionOriginalImage: UIImage? = nil
    var originalImage: UIImage? = nil
    var sourceImage: UIImage? = nil
    var currentReferenceName: String = "Reference"
    var currentSampleIdentifier: String? = nil
    var currentSessionID: UUID? = nil

    var processedImage: UIImage? = nil
    var paletteColors: [Color] = []
    var paletteBands: [Int] = []
    var pigmentRecipes: [PigmentRecipe]? = nil
    var selectedTubes: [PigmentData] = []
    var clippedRecipeIndices: [Int] = []
    var abstractedImage: UIImage? = nil
    var processedPixelBands: [Int] = []

    @ObservationIgnored let processOperation: ProcessOperation
    @ObservationIgnored let abstractionOperation: AbstractionOperation
    @ObservationIgnored let depthMapOperation: DepthMapOperation
    @ObservationIgnored let depthEffectOperation: DepthEffectOperation
    @ObservationIgnored var focusIsolationTask: Task<Void, Never>? = nil
    @ObservationIgnored var depthPreviewDismissTask: Task<Void, Never>? = nil
    @ObservationIgnored var contourTask: Task<Void, Never>? = nil
    @ObservationIgnored var presetPersistenceTask: Task<Void, Never>? = nil
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol? = nil
    @ObservationIgnored private(set) var sourceImageMetadata: SourceImageMetadata = .empty

    init(
        sessionStore: SessionStore? = nil,
        customPaletteStore: CustomPaletteStore? = nil,
        processOperation: ProcessOperation? = nil,
        abstractionOperation: AbstractionOperation? = nil,
        depthMapOperation: DepthMapOperation? = nil,
        depthEffectOperation: DepthEffectOperation? = nil
    ) {
        self.sessionStore = sessionStore ?? SessionStore()
        self.customPaletteStore = customPaletteStore ?? CustomPaletteStore()
        let processor = ImageProcessor()
        self.processOperation = processOperation ?? { image, mode, valueConfig, colorConfig, onProgress in
            try await processor.process(
                image: image,
                mode: mode,
                valueConfig: valueConfig,
                colorConfig: colorConfig,
                onProgress: onProgress
            )
        }
        self.abstractionOperation = abstractionOperation ?? { image, downscale, method, onProgress in
            try await ImageAbstractor.abstract(
                image: image,
                downscale: downscale,
                method: method,
                onProgress: onProgress
            )
        }
        self.depthMapOperation = depthMapOperation ?? { image in
            try await DepthEstimator.estimateDepth(from: image)
        }
        self.depthEffectOperation = depthEffectOperation ?? { image, depthMap, config in
            DepthProcessor.applyEffects(to: image, depthMap: depthMap, config: config)
        }

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ImageAbstractor.clearModelCache()
            DepthEstimator.clearModelCache()
        }

        restoreInitialTransformSnapshotSelection()
    }

    var displayBaseImage: UIImage? {
        abstractedImage ?? sourceImage
    }

    var currentDisplayImage: UIImage? {
        if depth.isEditingDepthThreshold, let preview = depth.depthThresholdPreview {
            return preview
        }

        let modeResult = transform.activeMode == .original
            ? displayBaseImage
            : (pipeline.isolatedProcessedImage ?? processedImage ?? displayBaseImage)

        if depth.depthConfig.enabled, let depthResult = depth.depthProcessedImage {
            return depthResult
        }

        return modeResult
    }

    var compareBeforeImage: UIImage? {
        originalImage ?? displayBaseImage
    }

    var compareAfterImage: UIImage? {
        transform.activeMode == .original ? displayBaseImage : currentDisplayImage
    }

    func sliderEditingChanged(_ editing: Bool) {
        pipeline.sliderEditingChanged(editing)
    }

    func band(atNormalizedPoint point: CGPoint) -> Int? {
        guard transform.activeMode == .value || transform.activeMode == .color,
              let processedImage,
              let cgImage = processedImage.cgImage,
              !processedPixelBands.isEmpty
        else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let x = min(max(Int((point.x * CGFloat(width)).rounded(.down)), 0), width - 1)
        let y = min(max(Int((point.y * CGFloat(height)).rounded(.down)), 0), height - 1)
        let pixelIndex = y * width + x
        guard processedPixelBands.indices.contains(pixelIndex) else { return nil }

        return processedPixelBands[pixelIndex]
    }

    func loadImage(_ image: UIImage) {
        loadImage(ImportedImagePayload(image: image))
    }

    func loadImage(_ payload: ImportedImagePayload) {
        loadImage(payload, restoredSnapshot: nil)
    }

    func restoreSession(_ session: StoredSession) {
        guard let image = sessionStore.image(for: session) else {
            pipeline.errorMessage = "That recent session could not be restored."
            return
        }

        currentSessionID = session.id
        loadImage(
            ImportedImagePayload(
                image: image,
                referenceName: session.referenceName,
                sampleIdentifier: session.sampleIdentifier
            ),
            restoredSnapshot: session.snapshot
        )
    }

    private func loadImage(
        _ payload: ImportedImagePayload,
        restoredSnapshot: TransformationSnapshot?
    ) {
        let image = payload.image

        AppState.depthLogger.info(
            "Loading image payload uti=\(payload.metadata.uniformTypeIdentifier ?? "unknown", privacy: .public) metadataKeys=\(payload.metadata.properties.count) embeddedDepthProvided=\(payload.embeddedDepthMap != nil)"
        )

        processing.cancel()
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()

        sourceImageMetadata = payload.metadata
        fullResolutionOriginalImage = image
        currentReferenceName = payload.referenceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (payload.referenceName ?? "Reference")
            : "Reference"
        currentSampleIdentifier = payload.sampleIdentifier
        if restoredSnapshot == nil {
            currentSessionID = nil
            applySuggestedSettings(from: payload)
        } else if let restoredSnapshot {
            loadTransformationSnapshot(restoredSnapshot)
        }
        Task {
            await AppTips.imageLoaded.donate()
            if payload.sampleIdentifier != nil {
                await AppTips.sampleLoaded.donate()
            }
        }

        originalImage = image
        sourceImage = image
        abstractedImage = nil
        clearDerivedOutputs()
        pipeline.errorMessage = nil
        pipeline.focusedBands = []
        pipeline.isolatedProcessedImage = nil

        depth.depthMap = nil
        depth.embeddedDepthMap = payload.embeddedDepthMap
        depth.depthSource = nil
        depth.depthProcessedImage = nil
        depth.depthThresholdPreview = nil
        depth.cachedDepthTexture = nil
        depth.cachedSourceTexture = nil
        depth.depthRange = 0...1
        depth.contourSegments = []
        depth.isEditingDepthThreshold = false
        depth.depthSliderActive = false

        let token = processing.start(
            for: .loadingImage,
            label: "Loading…",
            indeterminate: true,
            isSimplifying: true
        )

        processing.loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let maxSize: CGFloat = 1600
            let scaled = await image.scaledDownAsync(toMaxDimension: maxSize)

            try? Task.checkCancellation()
            guard !Task.isCancelled, self.processing.isCurrent(token) else { return }

            self.originalImage = scaled
            self.sourceImage = scaled
            self.persistCurrentSession()

            if self.transform.abstractionIsEnabled {
                self.applyAbstraction()
            } else {
                self.triggerProcessing()
            }
        }
    }

    func triggerProcessing() {
        processing.cancelScheduledProcessing()
        pipeline.errorMessage = nil
        updatePreviousTransformSnapshot()

        guard let source = displayBaseImage else {
            processing.finish()
            return
        }

        guard transform.activeMode != .original else {
            processedImage = nil
            processedPixelBands = []
            invalidateFocusIsolation(clearSelection: true)
            processing.finish()
            if depth.depthConfig.enabled && depth.depthMap != nil {
                applyDepthEffects()
            }
            return
        }

        invalidateFocusIsolation(clearSelection: true)

        let mode = transform.activeMode
        let token = processing.start(
            for: .transform(mode),
            label: "Processing…"
        )

        processing.processingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let result = try await self.processOperation(
                    source,
                    mode,
                    self.transform.valueConfig,
                    self.transform.colorConfig
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.processing.updateProgress(progress, token: token)
                    }
                }
                try Task.checkCancellation()
                guard self.processing.isCurrent(token) else { return }

                self.applyProcessingResult(result)
                self.processing.updateProgress(1, token: token)

                if self.depth.depthConfig.enabled && self.depth.depthMap != nil {
                    self.applyDepthEffects()
                } else {
                    self.processing.finish(token: token)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.pipeline.errorMessage = error.localizedDescription
                self.processing.finish(token: token)
            }
        }
    }

    func scheduleProcessing(after delay: Duration = .milliseconds(180)) {
        processing.processingDebounceTask?.cancel()
        updatePreviousTransformSnapshot()

        processing.processingDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.triggerProcessing()
            }
        }
    }

    func selectMode(_ mode: RefPlaneMode) {
        guard mode != transform.activeMode else { return }

        AppState.modeLogger.info(
            "mode-selected mode=\(mode.rawValue, privacy: .public)"
        )

        transform.activeMode = mode
        switch mode {
        case .original, .color:
            transform.valueConfig.grayscaleConversion = .none
        case .tonal, .value:
            if transform.valueConfig.grayscaleConversion == .none {
                transform.valueConfig.grayscaleConversion = .luminance
            }
        }

        clearDerivedOutputs()
        invalidateFocusIsolation(clearSelection: true)
        updatePreviousTransformSnapshot()
        triggerProcessing()
    }

    func setMode(_ mode: RefPlaneMode) {
        selectMode(mode)
    }

    func applyAbstraction() {
        guard let source = sourceImage else { return }
        guard transform.abstractionIsEnabled else {
            resetAbstraction()
            return
        }

        processing.abstractionTask?.cancel()

        let referenceResolution: CGFloat = 1600.0
        let maxDimension = max(source.size.width, source.size.height)
        let resolutionScale = maxDimension / referenceResolution
        let rawDownscale = 2.0 + transform.abstractionStrength * 10.0
        let downscale = max(1.0, CGFloat(rawDownscale) * resolutionScale)
        let method = transform.abstractionMethod

        pipeline.errorMessage = nil
        let token = processing.start(
            for: .abstraction,
            label: "Abstracting…",
            indeterminate: false,
            isSimplifying: true
        )

        processing.abstractionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let abstracted = try await self.abstractionOperation(
                    source,
                    downscale,
                    method
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.processing.updateProgress(progress, token: token)
                    }
                }
                try Task.checkCancellation()
                guard self.processing.isCurrent(token) else { return }

                self.abstractedImage = abstracted
                if self.depth.depthConfig.enabled {
                    self.computeDepthMap()
                }
                self.triggerProcessing()
            } catch is CancellationError {
                return
            } catch {
                self.pipeline.errorMessage = error.localizedDescription
                self.processing.finish(token: token)
            }
        }
    }

    func resetAbstraction() {
        processing.abstractionTask?.cancel()
        processing.abstractionTask = nil
        abstractedImage = nil
        processedPixelBands = []
        invalidateFocusIsolation(clearSelection: true)
        processing.finish()
        triggerProcessing()
    }

    func persistCurrentSession() {
        guard let referenceImage = fullResolutionOriginalImage ?? sourceImage else { return }

        currentSessionID = sessionStore.saveSession(
            id: currentSessionID,
            referenceName: currentReferenceName,
            image: referenceImage,
            snapshot: makeTransformationSnapshot(),
            sampleIdentifier: currentSampleIdentifier
        )
    }
}

private extension AppState {
    func applySuggestedSettings(from payload: ImportedImagePayload) {
        guard payload.suggestedMode != nil
            || payload.suggestedAbstractionStrength != nil
            || payload.suggestedBackgroundMode != nil
        else {
            return
        }

        if let suggestedMode = payload.suggestedMode {
            transform.activeMode = suggestedMode
            switch suggestedMode {
            case .original:
                transform.valueConfig.grayscaleConversion = .none
            case .tonal, .value:
                transform.valueConfig.grayscaleConversion = .luminance
            case .color:
                transform.valueConfig.grayscaleConversion = .none
                transform.colorConfig.paletteSelectionEnabled = true
            }
        }

        if let suggestedAbstractionStrength = payload.suggestedAbstractionStrength {
            transform.abstractionStrength = suggestedAbstractionStrength
        }

        if let suggestedBackgroundMode = payload.suggestedBackgroundMode {
            depth.depthConfig.backgroundMode = suggestedBackgroundMode
            depth.depthConfig.enabled = suggestedBackgroundMode != .none
        }
    }

    func clearDerivedOutputs() {
        processedImage = nil
        processedPixelBands = []
        paletteColors = []
        paletteBands = []
        pigmentRecipes = nil
        selectedTubes = []
        clippedRecipeIndices = []
    }

    func applyProcessingResult(_ result: ProcessingResult) {
        processedImage = result.image
        processedPixelBands = result.pixelBands
        paletteColors = result.palette
        paletteBands = result.paletteBands
        pigmentRecipes = result.pigmentRecipes
        selectedTubes = result.selectedTubes
        clippedRecipeIndices = result.clippedRecipeIndices
    }
}
