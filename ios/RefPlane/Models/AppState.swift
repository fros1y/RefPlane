import ImageIO
import SwiftUI
import Observation
import UniformTypeIdentifiers
import os

@Observable
@MainActor
class AppState {
    @ObservationIgnored static let depthLogger = Logger(subsystem: AppInstrumentation.subsystem, category: "DepthPipeline")

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

    // MARK: - Child state objects

    let transform = TransformState()
    let depth = DepthState()
    let pipeline = PipelineState()

    // MARK: - Source images

    var fullResolutionOriginalImage: UIImage? = nil
    var originalImage: UIImage? = nil
    var sourceImage: UIImage? = nil

    // MARK: - Processed results

    var processedImage: UIImage? = nil
    var paletteColors: [Color] = []
    var paletteBands: [Int] = []
    var pigmentRecipes: [PigmentRecipe]? = nil
    var selectedTubes: [PigmentData] = []
    var clippedRecipeIndices: [Int] = []

    // Abstracted image (after upscale/denoise)
    var abstractedImage: UIImage? = nil

    // MARK: - Internal infrastructure

    @ObservationIgnored private var processingTask: Task<Void, Never>? = nil
    @ObservationIgnored private var processingDebounceTask: Task<Void, Never>? = nil
    @ObservationIgnored let processOperation: ProcessOperation
    @ObservationIgnored private let abstractionOperation: AbstractionOperation
    @ObservationIgnored private var abstractionTask: Task<Void, Never>? = nil
    @ObservationIgnored var focusIsolationTask: Task<Void, Never>? = nil

    @ObservationIgnored private var loadingTask: Task<Void, Never>? = nil
    @ObservationIgnored private(set) var sourceImageMetadata: SourceImageMetadata = .empty
    var processedPixelBands: [Int] = []

    @ObservationIgnored let depthMapOperation: DepthMapOperation
    @ObservationIgnored let depthEffectOperation: DepthEffectOperation
    @ObservationIgnored var depthTask: Task<Void, Never>? = nil
    @ObservationIgnored var depthEffectTask: Task<Void, Never>? = nil
    @ObservationIgnored var depthPreviewDismissTask: Task<Void, Never>? = nil

    @ObservationIgnored var contourTask: Task<Void, Never>? = nil
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol? = nil
    @ObservationIgnored var presetPersistenceTask: Task<Void, Never>? = nil

    init(
        processOperation: ProcessOperation? = nil,
        abstractionOperation: AbstractionOperation? = nil,
        depthMapOperation: DepthMapOperation? = nil,
        depthEffectOperation: DepthEffectOperation? = nil
    ) {
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

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        loadingTask?.cancel()
        processingDebounceTask?.cancel()
        processingTask?.cancel()
        abstractionTask?.cancel()
        depthTask?.cancel()
        depthEffectTask?.cancel()
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()
        presetPersistenceTask?.cancel()
    }

    var displayBaseImage: UIImage? { abstractedImage ?? sourceImage }

    var currentDisplayImage: UIImage? {
        // While adjusting depth thresholds, show the threshold preview
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

    func band(atNormalizedPoint point: CGPoint) -> Int? {
        guard transform.activeMode == .value || transform.activeMode == .color,
              let processedImage,
              let cgImage = processedImage.cgImage,
              !processedPixelBands.isEmpty
        else { return nil }

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
        let image = payload.image

        AppState.depthLogger.info(
            "Loading image payload uti=\(payload.metadata.uniformTypeIdentifier ?? "unknown", privacy: .public) metadataKeys=\(payload.metadata.properties.count) embeddedDepthProvided=\(payload.embeddedDepthMap != nil)"
        )

        // Cancel any in-flight work before starting fresh.
        loadingTask?.cancel()
        processingDebounceTask?.cancel()
        processingTask?.cancel()
        abstractionTask?.cancel()
        depthTask?.cancel()
        depthEffectTask?.cancel()
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()

        if let suggestedMode = payload.suggestedMode, suggestedMode != transform.activeMode {
            transform.activeMode = suggestedMode
            normalizeGrayscaleConversion(for: suggestedMode)
        }

        // Invalidate stale completions in case any task ignores cancellation.

        // Show the picked image immediately, then swap in the scaled version
        // once preprocessing finishes so the canvas never blanks out.
        sourceImageMetadata        = payload.metadata
        fullResolutionOriginalImage   = image
        Task {
            await AppTips.imageLoaded.donate()
        }
        originalImage                      = image
        sourceImage                        = image
        abstractedImage                    = nil
        processedImage                     = nil
        pipeline.isolatedProcessedImage    = nil
        depth.depthMap                     = nil
        depth.embeddedDepthMap             = payload.embeddedDepthMap
        depth.depthSource                  = nil
        depth.depthProcessedImage          = nil
        depth.depthThresholdPreview        = nil
        depth.cachedDepthTexture           = nil
        depth.cachedSourceTexture          = nil
        depth.depthRange                   = 0...1
        depth.contourSegments              = []
        processedPixelBands                = []
        paletteColors                      = []
        paletteBands                       = []
        pigmentRecipes                     = nil
        selectedTubes                      = []
        clippedRecipeIndices               = []
        pipeline.focusedBands              = []
        pipeline.errorMessage              = nil
        pipeline.isProcessing              = true
        pipeline.isSimplifying             = true
        pipeline.processingProgress        = 0
        pipeline.processingLabel           = "Loading…"
        pipeline.processingIsIndeterminate = true

        loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let maxSize: CGFloat = 1600
            let scaled = await image.scaledDownAsync(toMaxDimension: maxSize)

            try? Task.checkCancellation()
            guard !Task.isCancelled else { return }

            self.originalImage             = scaled
            self.sourceImage               = scaled
            if self.transform.abstractionIsEnabled {
                self.applyAbstraction()
            } else {
                self.pipeline.isSimplifying             = false
                self.pipeline.processingLabel           = "Processing…"
                self.pipeline.processingIsIndeterminate = false
                self.triggerProcessing()
            }
        }
    }

    func triggerProcessing() {
        processingDebounceTask?.cancel()
        processingTask?.cancel()
        pipeline.processingIsIndeterminate = false
        pipeline.errorMessage = nil
        updatePreviousTransformSnapshot()
        guard let source = displayBaseImage else {
            pipeline.isProcessing = false
            pipeline.processingProgress = 0
            return
        }
        guard transform.activeMode != .original else {
            processedImage = nil
            processedPixelBands = []
            invalidateFocusIsolation(clearSelection: true)
            pipeline.isProcessing = false
            pipeline.processingProgress = 0
            if depth.depthConfig.enabled && depth.depthMap != nil {
                applyDepthEffects()
            }
            return
        }

        // Set processing state synchronously so the UI shows the spinner
        // on the very first SwiftUI render after the mode change.
        invalidateFocusIsolation(clearSelection: true)
        pipeline.isProcessing = true
        pipeline.processingProgress = 0

        let mode = transform.activeMode

        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.processOperation(
                    source,
                    mode,
                    self.transform.valueConfig,
                    self.transform.colorConfig,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.pipeline.processingProgress = p }
                    }
                )
                try Task.checkCancellation()

                self.processedImage      = result.image
                self.processedPixelBands = result.pixelBands
                self.paletteColors       = result.palette
                self.paletteBands        = result.paletteBands
                self.pigmentRecipes      = result.pigmentRecipes
                self.selectedTubes       = result.selectedTubes
                self.clippedRecipeIndices = result.clippedRecipeIndices
                self.pipeline.processingProgress  = 1
                if self.depth.depthConfig.enabled && self.depth.depthMap != nil {
                    self.applyDepthEffects()
                }
            } catch is CancellationError {
                // Mode switched or new image loaded — new task will update state
            } catch {
                if !Task.isCancelled {
                    self.pipeline.errorMessage = error.localizedDescription
                }
            }

            // Only clear the flag if depth-effect rendering hasn't taken ownership of the indicator.
            if !Task.isCancelled && !(self.depth.depthConfig.enabled && self.depth.depthMap != nil) {
                self.pipeline.isProcessing = false
            }
        }
    }

    func scheduleProcessing(after delay: Duration = .milliseconds(180)) {
        processingDebounceTask?.cancel()
        updatePreviousTransformSnapshot()

        processingDebounceTask = Task { [weak self] in
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

    func setMode(_ mode: RefPlaneMode) {
        guard mode != transform.activeMode else { return }
        transform.activeMode = mode
        normalizeGrayscaleConversion(for: mode)
        processedImage = nil
        invalidateFocusIsolation(clearSelection: true)
        processedPixelBands = []
        paletteColors = []
        paletteBands = []
        pigmentRecipes = nil
        selectedTubes = []
        clippedRecipeIndices = []
        updatePreviousTransformSnapshot()
        triggerProcessing()
    }

    /// Keep the grayscale conversion consistent with the mode: color-bearing
    /// modes use none; tonal modes need a concrete conversion.
    private func normalizeGrayscaleConversion(for mode: RefPlaneMode) {
        switch mode {
        case .original, .color:
            transform.valueConfig.grayscaleConversion = .none
        case .tonal, .value:
            if transform.valueConfig.grayscaleConversion == .none {
                transform.valueConfig.grayscaleConversion = .luminance
            }
        }
    }

    func applyAbstraction() {
        guard let source = sourceImage else { return }
        guard transform.abstractionIsEnabled else {
            resetAbstraction()
            return
        }

        abstractionTask?.cancel()

        // Normalize the downscale factor to the image resolution so that the
        // absolute intermediate pixel size — what determines the visual degree of
        // abstraction — stays consistent regardless of the input dimensions.
        // At the reference resolution (1600 px) the mapping is the full 2–12×
        // range; for smaller images the factor scales down proportionally so that
        // lower-resolution photos are not over-abstracted at the same slider value.
        let referenceResolution: CGFloat = 1600.0
        let maxDimension = max(source.size.width, source.size.height)
        let resolutionScale = maxDimension / referenceResolution
        let rawDownscale = 2.0 + transform.abstractionStrength * 10.0
        let downscale = max(1.0, CGFloat(rawDownscale) * resolutionScale)
        let method = transform.abstractionMethod

        pipeline.isProcessing = true
        pipeline.isSimplifying = true
        pipeline.processingProgress = 0
        pipeline.processingLabel = "Abstracting…"
        pipeline.processingIsIndeterminate = false
        pipeline.errorMessage = nil

        abstractionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let abstracted = try await self.abstractionOperation(
                    source,
                    downscale,
                    method,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.pipeline.processingProgress = p }
                    }
                )
                try Task.checkCancellation()

                self.abstractedImage = abstracted
                self.pipeline.isSimplifying   = false
                self.pipeline.isProcessing    = false
                self.pipeline.processingLabel = "Processing…"
                if self.depth.depthConfig.enabled {
                    self.computeDepthMap()
                }
                self.triggerProcessing()
            } catch is CancellationError {
                // superseded by a newer request
            } catch {
                self.pipeline.isSimplifying = false
                self.pipeline.isProcessing = false
                self.pipeline.processingLabel = "Processing…"
                self.pipeline.errorMessage = error.localizedDescription
            }
        }
    }

    func resetAbstraction() {
        abstractionTask?.cancel()
        pipeline.isSimplifying = false
        abstractedImage = nil
        processedPixelBands = []
        invalidateFocusIsolation(clearSelection: true)
        pipeline.processingLabel = "Processing…"
        pipeline.processingIsIndeterminate = false
        triggerProcessing()
    }

}
