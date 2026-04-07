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
    @ObservationIgnored private let processOperation: ProcessOperation
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

    // MARK: - TransformState forwarding

    var activeMode: RefPlaneMode {
        get { transform.activeMode }
        set { transform.activeMode = newValue }
    }

    var gridConfig: GridConfig {
        get { transform.gridConfig }
        set { transform.gridConfig = newValue }
    }

    var valueConfig: ValueConfig {
        get { transform.valueConfig }
        set { transform.valueConfig = newValue }
    }

    var colorConfig: ColorConfig {
        get { transform.colorConfig }
        set { transform.colorConfig = newValue }
    }

    var contourConfig: ContourConfig {
        get { transform.contourConfig }
        set { transform.contourConfig = newValue }
    }

    var abstractionStrength: Double {
        get { transform.abstractionStrength }
        set { transform.abstractionStrength = newValue }
    }

    var abstractionMethod: AbstractionMethod {
        get { transform.abstractionMethod }
        set { transform.abstractionMethod = newValue }
    }

    var previousTransformSnapshot: TransformationSnapshot? {
        get { transform.previousTransformSnapshot }
        set { transform.previousTransformSnapshot = newValue }
    }

    var selectedTransformPresetSelection: TransformPresetSelection {
        get { transform.selectedTransformPresetSelection }
        set { transform.selectedTransformPresetSelection = newValue }
    }

    var presetManager: TransformPresetManager {
        get { transform.presetManager }
        set { transform.presetManager = newValue }
    }

    var savedTransformPresets: [SavedTransformPreset] {
        transform.savedTransformPresets
    }

    var abstractionIsEnabled: Bool {
        transform.abstractionIsEnabled
    }

    var availableAbstractionMethods: [AbstractionMethod] {
        transform.availableAbstractionMethods
    }

    // MARK: - DepthState forwarding

    var depthConfig: DepthConfig {
        get { depth.depthConfig }
        set { depth.depthConfig = newValue }
    }

    var depthMap: UIImage? {
        get { depth.depthMap }
        set { depth.depthMap = newValue }
    }

    var embeddedDepthMap: UIImage? {
        get { depth.embeddedDepthMap }
        set { depth.embeddedDepthMap = newValue }
    }

    var depthSource: DepthSource? {
        get { depth.depthSource }
        set { depth.depthSource = newValue }
    }

    var depthProcessedImage: UIImage? {
        get { depth.depthProcessedImage }
        set { depth.depthProcessedImage = newValue }
    }

    var depthRange: ClosedRange<Double> {
        get { depth.depthRange }
        set { depth.depthRange = newValue }
    }

    var isEditingDepthThreshold: Bool {
        get { depth.isEditingDepthThreshold }
        set { depth.isEditingDepthThreshold = newValue }
    }

    var depthThresholdPreview: UIImage? {
        get { depth.depthThresholdPreview }
        set { depth.depthThresholdPreview = newValue }
    }

    var contourSegments: [GridLineSegment] {
        get { depth.contourSegments }
        set { depth.contourSegments = newValue }
    }

    var cachedDepthTexture: AnyObject? {
        get { depth.cachedDepthTexture }
        set { depth.cachedDepthTexture = newValue }
    }

    var cachedSourceTexture: AnyObject? {
        get { depth.cachedSourceTexture }
        set { depth.cachedSourceTexture = newValue }
    }

    var depthSliderActive: Bool {
        get { depth.depthSliderActive }
        set { depth.depthSliderActive = newValue }
    }

    // MARK: - PipelineState forwarding

    var isProcessing: Bool {
        get { pipeline.isProcessing }
        set { pipeline.isProcessing = newValue }
    }

    var isSimplifying: Bool {
        get { pipeline.isSimplifying }
        set { pipeline.isSimplifying = newValue }
    }

    var processingProgress: Double {
        get { pipeline.processingProgress }
        set { pipeline.processingProgress = newValue }
    }

    var processingLabel: String {
        get { pipeline.processingLabel }
        set { pipeline.processingLabel = newValue }
    }

    var processingIsIndeterminate: Bool {
        get { pipeline.processingIsIndeterminate }
        set { pipeline.processingIsIndeterminate = newValue }
    }

    var compareMode: Bool {
        get { pipeline.compareMode }
        set { pipeline.compareMode = newValue }
    }

    var focusedBands: Set<Int> {
        get { pipeline.focusedBands }
        set { pipeline.focusedBands = newValue }
    }

    var errorMessage: String? {
        get { pipeline.errorMessage }
        set { pipeline.errorMessage = newValue }
    }

    var panelCollapsed: Bool {
        get { pipeline.panelCollapsed }
        set { pipeline.panelCollapsed = newValue }
    }

    var isolatedProcessedImage: UIImage? {
        get { pipeline.isolatedProcessedImage }
        set { pipeline.isolatedProcessedImage = newValue }
    }

    var activeSliderCount: Int {
        get { pipeline.activeSliderCount }
        set { pipeline.activeSliderCount = newValue }
    }

    var isAnySliderActive: Bool {
        get { pipeline.isAnySliderActive }
        set { pipeline.isAnySliderActive = newValue }
    }

    func sliderEditingChanged(_ editing: Bool) {
        pipeline.sliderEditingChanged(editing)
    }


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
        if isEditingDepthThreshold, let preview = depthThresholdPreview {
            return preview
        }
        let modeResult = activeMode == .original
            ? displayBaseImage
            : (isolatedProcessedImage ?? processedImage ?? displayBaseImage)
        if depthConfig.enabled, let depthResult = depthProcessedImage {
            return depthResult
        }
        return modeResult
    }

    var compareBeforeImage: UIImage? {
        originalImage ?? displayBaseImage
    }

    var compareAfterImage: UIImage? {
        activeMode == .original ? displayBaseImage : currentDisplayImage
    }

    func band(atNormalizedPoint point: CGPoint) -> Int? {
        guard activeMode == .value || activeMode == .color,
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

        // Invalidate stale completions in case any task ignores cancellation.

        // Show the picked image immediately, then swap in the scaled version
        // once preprocessing finishes so the canvas never blanks out.
        sourceImageMetadata        = payload.metadata
        fullResolutionOriginalImage   = image
        Task {
            await AppTips.imageLoaded.donate()
        }
        originalImage             = image
        sourceImage               = image
        abstractedImage           = nil
        processedImage            = nil
        isolatedProcessedImage    = nil
        depthMap                  = nil
        embeddedDepthMap          = payload.embeddedDepthMap
        depthSource               = nil
        depthProcessedImage       = nil
        depthThresholdPreview     = nil
        cachedDepthTexture        = nil
        cachedSourceTexture       = nil
        depthRange                = 0...1
        contourSegments           = []
        processedPixelBands       = []
        paletteColors             = []
        paletteBands              = []
        pigmentRecipes            = nil
        selectedTubes             = []
        clippedRecipeIndices      = []
        focusedBands              = []
        errorMessage              = nil
        isProcessing              = true
        isSimplifying             = true
        processingProgress        = 0
        processingLabel           = "Loading…"
        processingIsIndeterminate = true

        loadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let maxSize: CGFloat = 1600
            let scaled = await image.scaledDownAsync(toMaxDimension: maxSize)
            
            try? Task.checkCancellation()
            guard !Task.isCancelled else { return }
            
            self.originalImage             = scaled
            self.sourceImage               = scaled
            if self.abstractionIsEnabled {
                self.applyAbstraction()
            } else {
                self.isSimplifying             = false
                self.processingLabel           = "Processing…"
                self.processingIsIndeterminate = false
                self.triggerProcessing()
            }
        }
    }

    func triggerProcessing() {
        processingDebounceTask?.cancel()
        processingTask?.cancel()
        processingIsIndeterminate = false
        errorMessage = nil
        updatePreviousTransformSnapshot()
        guard let source = displayBaseImage else {
            isProcessing = false
            processingProgress = 0
            return
        }
        guard activeMode != .original else {
            processedImage = nil
            processedPixelBands = []
            invalidateFocusIsolation(clearSelection: true)
            isProcessing = false
            processingProgress = 0
            if depthConfig.enabled && depthMap != nil {
                applyDepthEffects()
            }
            return
        }

        // Set processing state synchronously so the UI shows the spinner
        // on the very first SwiftUI render after the mode change.
    invalidateFocusIsolation(clearSelection: true)
        isProcessing = true
        processingProgress = 0

        let mode = activeMode

        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.processOperation(
                    source,
                    mode,
                    self.valueConfig,
                    self.colorConfig,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.processingProgress = p }
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
                self.processingProgress  = 1
                if self.depthConfig.enabled && self.depthMap != nil {
                    self.applyDepthEffects()
                }
            } catch is CancellationError {
                // Mode switched or new image loaded — new task will update state
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            
            // Only clear the flag if depth-effect rendering hasn't taken ownership of the indicator.
            if !Task.isCancelled && !(self.depthConfig.enabled && self.depthMap != nil) {
                self.isProcessing = false
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
        guard mode != activeMode else { return }
        activeMode = mode
        switch mode {
        case .original, .color:
            valueConfig.grayscaleConversion = .none
        case .tonal, .value:
            if valueConfig.grayscaleConversion == .none {
                valueConfig.grayscaleConversion = .luminance
            }
        }
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



    func applyAbstraction() {
        guard let source = sourceImage else { return }
        guard abstractionIsEnabled else {
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
        let rawDownscale = 2.0 + abstractionStrength * 10.0
        let downscale = max(1.0, CGFloat(rawDownscale) * resolutionScale)
        let method = abstractionMethod

        isProcessing = true
        isSimplifying = true
        processingProgress = 0
        processingLabel = "Abstracting…"
        processingIsIndeterminate = false
        errorMessage = nil

        abstractionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let abstracted = try await self.abstractionOperation(
                    source,
                    downscale,
                    method,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.processingProgress = p }
                    }
                )
                try Task.checkCancellation()

                self.abstractedImage = abstracted
                self.isSimplifying   = false
                self.isProcessing    = false
                self.processingLabel = "Processing…"
                if self.depthConfig.enabled {
                    self.computeDepthMap()
                }
                self.triggerProcessing()
            } catch is CancellationError {
                // superseded by a newer request
            } catch {
                self.isSimplifying = false
                self.isProcessing = false
                self.processingLabel = "Processing…"
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func resetAbstraction() {
        abstractionTask?.cancel()
        isSimplifying = false
        abstractedImage = nil
        processedPixelBands = []
        invalidateFocusIsolation(clearSelection: true)
        processingLabel = "Processing…"
        processingIsIndeterminate = false
        triggerProcessing()
    }

}
