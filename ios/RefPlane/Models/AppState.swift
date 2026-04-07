import ImageIO
import SwiftUI
import Observation
import UniformTypeIdentifiers
import os

@Observable
@MainActor
class AppState {
    @ObservationIgnored private static let depthLogger = Logger(subsystem: "com.refplane.app", category: "DepthPipeline")
    enum TransformPresetSelection: Hashable {
        case previous
        case appDefault
        case saved(UUID)
    }

    enum TransformPresetError: LocalizedError {
        case emptyName
        case duplicateName
        case presetNotFound

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Preset name cannot be empty."
            case .duplicateName:
                return "A preset with that name already exists."
            case .presetNotFound:
                return "Preset not found."
            }
        }
    }

    struct SavedTransformPreset: Identifiable, Codable, Equatable {
        var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var snapshot: TransformationSnapshot
    }

    struct CodableColor: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        init(_ color: Color) {
            let uiColor = UIColor(color)
            var redComponent: CGFloat = 0
            var greenComponent: CGFloat = 0
            var blueComponent: CGFloat = 0
            var alphaComponent: CGFloat = 0

            if uiColor.getRed(
                &redComponent,
                green: &greenComponent,
                blue: &blueComponent,
                alpha: &alphaComponent
            ) {
                red = redComponent
                green = greenComponent
                blue = blueComponent
                alpha = alphaComponent
            } else {
                red = 1
                green = 1
                blue = 1
                alpha = 1
            }
        }

        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        }
    }

    struct TransformationSnapshot: Codable, Equatable {
        var activeMode: RefPlaneMode
        var abstractionStrength: Double
        var abstractionMethod: AbstractionMethod

        var gridEnabled: Bool
        var gridDivisions: Int
        var gridShowDiagonals: Bool
        var gridLineStyle: LineStyle
        var gridCustomColor: CodableColor
        var gridOpacity: Double

        var grayscaleConversion: GrayscaleConversion
        var valueLevels: Int
        var valueThresholds: [Double]
        var valueDistribution: ThresholdDistribution
        var valueQuantizationBias: Double

        var paletteSelectionEnabled: Bool
        var colorLimit: Int
        var enabledPigmentIDs: [String]
        var paletteSpread: Double
        var colorQuantizationBias: Double
        var maxPigmentsPerMix: Int
        var minConcentration: Float

        var depthEnabled: Bool
        var foregroundCutoff: Double
        var backgroundCutoff: Double
        var depthEffectIntensity: Double
        var backgroundMode: BackgroundMode

        var contourEnabled: Bool
        var contourLevels: Int
        var contourLineStyle: LineStyle
        var contourCustomColor: CodableColor
        var contourOpacity: Double

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            activeMode = try c.decode(RefPlaneMode.self, forKey: .activeMode)
            abstractionStrength = try c.decode(Double.self, forKey: .abstractionStrength)
            abstractionMethod = try c.decode(AbstractionMethod.self, forKey: .abstractionMethod)
            gridEnabled = try c.decode(Bool.self, forKey: .gridEnabled)
            gridDivisions = try c.decode(Int.self, forKey: .gridDivisions)
            gridShowDiagonals = try c.decode(Bool.self, forKey: .gridShowDiagonals)
            gridLineStyle = try c.decode(LineStyle.self, forKey: .gridLineStyle)
            gridCustomColor = try c.decode(CodableColor.self, forKey: .gridCustomColor)
            gridOpacity = try c.decode(Double.self, forKey: .gridOpacity)
            grayscaleConversion = try c.decode(GrayscaleConversion.self, forKey: .grayscaleConversion)
            valueLevels = try c.decode(Int.self, forKey: .valueLevels)
            valueThresholds = try c.decode([Double].self, forKey: .valueThresholds)
            valueDistribution = try c.decode(ThresholdDistribution.self, forKey: .valueDistribution)
            valueQuantizationBias = try c.decode(Double.self, forKey: .valueQuantizationBias)
            paletteSelectionEnabled = try c.decode(Bool.self, forKey: .paletteSelectionEnabled)
            colorLimit = try c.decode(Int.self, forKey: .colorLimit)
            enabledPigmentIDs = try c.decode([String].self, forKey: .enabledPigmentIDs)
            paletteSpread = try c.decode(Double.self, forKey: .paletteSpread)
            colorQuantizationBias = try c.decode(Double.self, forKey: .colorQuantizationBias)
            maxPigmentsPerMix = try c.decode(Int.self, forKey: .maxPigmentsPerMix)
            minConcentration = try c.decode(Float.self, forKey: .minConcentration)
            depthEnabled = try c.decode(Bool.self, forKey: .depthEnabled)
            foregroundCutoff = try c.decode(Double.self, forKey: .foregroundCutoff)
            backgroundCutoff = try c.decode(Double.self, forKey: .backgroundCutoff)
            depthEffectIntensity = try c.decode(Double.self, forKey: .depthEffectIntensity)
            backgroundMode = try c.decode(BackgroundMode.self, forKey: .backgroundMode)
            contourEnabled = try c.decode(Bool.self, forKey: .contourEnabled)
            contourLevels = try c.decode(Int.self, forKey: .contourLevels)
            contourLineStyle = try c.decode(LineStyle.self, forKey: .contourLineStyle)
            contourCustomColor = try c.decode(CodableColor.self, forKey: .contourCustomColor)
            contourOpacity = try c.decode(Double.self, forKey: .contourOpacity)
        }

        // Explicit memberwise init (required because custom init(from:) suppresses synthesis).
        init(
            activeMode: RefPlaneMode,
            abstractionStrength: Double,
            abstractionMethod: AbstractionMethod,
            gridEnabled: Bool,
            gridDivisions: Int,
            gridShowDiagonals: Bool,
            gridLineStyle: LineStyle,
            gridCustomColor: CodableColor,
            gridOpacity: Double,
            grayscaleConversion: GrayscaleConversion,
            valueLevels: Int,
            valueThresholds: [Double],
            valueDistribution: ThresholdDistribution,
            valueQuantizationBias: Double,
            paletteSelectionEnabled: Bool,
            colorLimit: Int,
            enabledPigmentIDs: [String],
            paletteSpread: Double,
            colorQuantizationBias: Double,
            maxPigmentsPerMix: Int,
            minConcentration: Float,
            depthEnabled: Bool,
            foregroundCutoff: Double,
            backgroundCutoff: Double,
            depthEffectIntensity: Double,
            backgroundMode: BackgroundMode,
            contourEnabled: Bool,
            contourLevels: Int,
            contourLineStyle: LineStyle,
            contourCustomColor: CodableColor,
            contourOpacity: Double
        ) {
            self.activeMode = activeMode
            self.abstractionStrength = abstractionStrength
            self.abstractionMethod = abstractionMethod
            self.gridEnabled = gridEnabled
            self.gridDivisions = gridDivisions
            self.gridShowDiagonals = gridShowDiagonals
            self.gridLineStyle = gridLineStyle
            self.gridCustomColor = gridCustomColor
            self.gridOpacity = gridOpacity
            self.grayscaleConversion = grayscaleConversion
            self.valueLevels = valueLevels
            self.valueThresholds = valueThresholds
            self.valueDistribution = valueDistribution
            self.valueQuantizationBias = valueQuantizationBias
            self.paletteSelectionEnabled = paletteSelectionEnabled
            self.colorLimit = colorLimit
            self.enabledPigmentIDs = enabledPigmentIDs
            self.paletteSpread = paletteSpread
            self.colorQuantizationBias = colorQuantizationBias
            self.maxPigmentsPerMix = maxPigmentsPerMix
            self.minConcentration = minConcentration
            self.depthEnabled = depthEnabled
            self.foregroundCutoff = foregroundCutoff
            self.backgroundCutoff = backgroundCutoff
            self.depthEffectIntensity = depthEffectIntensity
            self.backgroundMode = backgroundMode
            self.contourEnabled = contourEnabled
            self.contourLevels = contourLevels
            self.contourLineStyle = contourLineStyle
            self.contourCustomColor = contourCustomColor
            self.contourOpacity = contourOpacity
        }
    }

    private struct TransformPresetStore: Codable {
        var schemaVersion: Int
        var savedPresets: [SavedTransformPreset]
        var previousSnapshot: TransformationSnapshot?
    }

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

    // Source images
    var fullResolutionOriginalImage: UIImage? = nil
    var originalImage: UIImage? = nil
    var sourceImage: UIImage? = nil

    // Processed results
    var processedImage: UIImage? = nil
    var paletteColors: [Color] = []
    var paletteBands: [Int] = []
    var pigmentRecipes: [PigmentRecipe]? = nil
    var selectedTubes: [PigmentData] = []
    var clippedRecipeIndices: [Int] = []

    // UI state
    var activeMode: RefPlaneMode = .original
    var isProcessing: Bool = false
    /// `true` while the image is being loaded or simplified (abstracted);
    /// `false` during actual mode processing. Used to suppress the blur
    /// overlay so the original image stays crisp during simplification.
    var isSimplifying: Bool = false
    var processingProgress: Double = 0
    var processingLabel: String = "Processing…"
    var processingIsIndeterminate: Bool = false
    var compareMode: Bool = false
    var focusedBands: Set<Int> = []
    var errorMessage: String? = nil
    var panelCollapsed: Bool = false
    private(set) var isolatedProcessedImage: UIImage? = nil

    // Configs
    var gridConfig: GridConfig = GridConfig()
    var valueConfig: ValueConfig = ValueConfig()
    var colorConfig: ColorConfig = ColorConfig()
    var depthConfig: DepthConfig = DepthConfig()
    var contourConfig: ContourConfig = ContourConfig()
    var contourSegments: [GridLineSegment] = []

    // Transformation preset state
    var savedTransformPresets: [SavedTransformPreset] = []
    var previousTransformSnapshot: TransformationSnapshot? = nil
    var selectedTransformPresetSelection: TransformPresetSelection = .previous

    // Depth results
    var depthMap: UIImage? = nil
    var embeddedDepthMap: UIImage? = nil
    var depthSource: DepthSource? = nil
    var depthProcessedImage: UIImage? = nil
    /// Actual min/max depth values found in the current depth map (0–1 scale).
    var depthRange: ClosedRange<Double> = 0...1
    /// When true, the canvas shows a depth-threshold preview instead of the
    /// processed image. Set while the user drags a depth cutoff slider.
    var isEditingDepthThreshold: Bool = false
    /// Cached depth-threshold preview image, regenerated as cutoffs change.
    var depthThresholdPreview: UIImage? = nil
    /// Cached Metal texture of the depth map, reused across preview updates for speed.
    @ObservationIgnored var cachedDepthTexture: AnyObject? = nil
    /// Cached Metal texture of the preview source image, reused during slider drags.
    @ObservationIgnored var cachedSourceTexture: AnyObject? = nil
    /// True while the user's finger is actively on a depth cutoff slider.
    @ObservationIgnored var depthSliderActive: Bool = false

    // MARK: - Active slider tracking

    /// Number of sliders currently being dragged. Tracked so the bottom panel
    /// can collapse while any slider is active, giving the user a clear view
    /// of the canvas.
    @ObservationIgnored var activeSliderCount: Int = 0

    /// Convenience: true when any slider is being interacted with.
    var isAnySliderActive: Bool = false

    func sliderEditingChanged(_ editing: Bool) {
        activeSliderCount += editing ? 1 : -1
        if activeSliderCount < 0 {
            activeSliderCount = 0
        }
        isAnySliderActive = activeSliderCount > 0
    }

    /// Abstraction strength 0–1. `0` disables abstraction; positive values map
    /// to the existing downscale-based abstraction range.
    var abstractionStrength: Double = 0.5
    var abstractionMethod: AbstractionMethod = .apisr

    // Abstracted image (after upscale/denoise)
    var abstractedImage: UIImage? = nil

    @ObservationIgnored private var processingTask: Task<Void, Never>? = nil
    @ObservationIgnored private var processingDebounceTask: Task<Void, Never>? = nil
    @ObservationIgnored private let processOperation: ProcessOperation
    /// Incremented on every triggerProcessing() call; lets each task know if it is still current.

    @ObservationIgnored private let abstractionOperation: AbstractionOperation
    @ObservationIgnored private var abstractionTask: Task<Void, Never>? = nil
    @ObservationIgnored private var focusIsolationTask: Task<Void, Never>? = nil

    @ObservationIgnored private var loadingTask: Task<Void, Never>? = nil
    @ObservationIgnored private(set) var sourceImageMetadata: SourceImageMetadata = .empty
    private var processedPixelBands: [Int] = []

    @ObservationIgnored private let depthMapOperation: DepthMapOperation
    @ObservationIgnored private let depthEffectOperation: DepthEffectOperation
    @ObservationIgnored private var depthTask: Task<Void, Never>? = nil
    @ObservationIgnored private var depthEffectTask: Task<Void, Never>? = nil
    @ObservationIgnored private var depthPreviewDismissTask: Task<Void, Never>? = nil

    @ObservationIgnored private var contourTask: Task<Void, Never>? = nil
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol? = nil
    @ObservationIgnored private var presetPersistenceTask: Task<Void, Never>? = nil

    @ObservationIgnored private static let transformPresetStoreKey = "AppState.transformPresetStore.v1"

    var abstractionIsEnabled: Bool {
        abstractionStrength > 0
    }

    var availableAbstractionMethods: [AbstractionMethod] {
        AbstractionMethod.allCases.filter { method in
            switch method.processingKind {
            case .superResolution4x, .fullImageModel:
                guard let name = method.modelBundleName else { return false }
                return Bundle.main.url(forResource: name, withExtension: "mlmodelc") != nil
                    || Bundle.main.url(forResource: name, withExtension: "mlpackage") != nil
                    || Bundle.main.url(forResource: name, withExtension: "mlmodel") != nil
            }
        }
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

        loadTransformPresetStore()
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

    var hasPreviousTransformSnapshot: Bool {
        previousTransformSnapshot != nil
    }

    var shouldShowPreviousSettingsOption: Bool {
        guard let previousTransformSnapshot else { return true }
        return matchingSavedPresetID(for: previousTransformSnapshot) == nil
    }

    var availableTransformPresetSelections: [TransformPresetSelection] {
        var options: [TransformPresetSelection] = []
        if shouldShowPreviousSettingsOption {
            options.append(.previous)
        }
        options.append(.appDefault)
        options.append(contentsOf: savedTransformPresets.map { .saved($0.id) })
        return options
    }

    var selectedTransformPresetLabel: String {
        label(for: selectedTransformPresetSelection)
    }

    func label(for selection: TransformPresetSelection) -> String {
        switch selection {
        case .previous:
            return "Previous Settings"
        case .appDefault:
            return "Default"
        case .saved(let presetID):
            return savedTransformPresets.first(where: { $0.id == presetID })?.name ?? "Saved Settings"
        }
    }

    func saveCurrentTransformPreset(named rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw TransformPresetError.emptyName
        }

        let normalizedName = normalizedPresetName(name)
        guard !savedTransformPresets.contains(where: { normalizedPresetName($0.name) == normalizedName }) else {
            throw TransformPresetError.duplicateName
        }

        let now = Date()
        let preset = SavedTransformPreset(
            id: UUID(),
            name: name,
            createdAt: now,
            updatedAt: now,
            snapshot: makeTransformationSnapshot()
        )

        savedTransformPresets.append(preset)
        savedTransformPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedTransformPresetSelection = .saved(preset.id)
        persistTransformPresetStore()
    }

    func renameTransformPreset(id: UUID, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw TransformPresetError.emptyName
        }

        let normalizedName = normalizedPresetName(name)
        guard !savedTransformPresets.contains(where: {
            $0.id != id && normalizedPresetName($0.name) == normalizedName
        }) else {
            throw TransformPresetError.duplicateName
        }

        guard let index = savedTransformPresets.firstIndex(where: { $0.id == id }) else {
            throw TransformPresetError.presetNotFound
        }

        savedTransformPresets[index].name = name
        savedTransformPresets[index].updatedAt = Date()
        savedTransformPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistTransformPresetStore()
    }

    func deleteTransformPreset(id: UUID) {
        savedTransformPresets.removeAll { $0.id == id }
        selectedTransformPresetSelection = canonicalSelectionForCurrentSettings()
        persistTransformPresetStore()
    }

    func selectTransformPreset(_ selection: TransformPresetSelection) {
        switch selection {
        case .previous:
            if let previousTransformSnapshot {
                applyTransformationSnapshot(previousTransformSnapshot)
            }
        case .appDefault:
            applyTransformationSnapshot(Self.defaultTransformationSnapshot())
        case .saved(let presetID):
            guard let preset = savedTransformPresets.first(where: { $0.id == presetID }) else { return }
            applyTransformationSnapshot(preset.snapshot)
        }

        selectedTransformPresetSelection = canonicalSelectionForCurrentSettings()
    }

    func suggestedTransformPresetName() -> String {
        var index = 1
        while true {
            let candidate = "Preset \(index)"
            let normalized = normalizedPresetName(candidate)
            if !savedTransformPresets.contains(where: { normalizedPresetName($0.name) == normalized }) {
                return candidate
            }
            index += 1
        }
    }

    private func normalizedPresetName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func makeTransformationSnapshot() -> TransformationSnapshot {
        TransformationSnapshot(
            activeMode: activeMode,
            abstractionStrength: abstractionStrength,
            abstractionMethod: abstractionMethod,
            gridEnabled: gridConfig.enabled,
            gridDivisions: gridConfig.divisions,
            gridShowDiagonals: gridConfig.showDiagonals,
            gridLineStyle: gridConfig.lineStyle,
            gridCustomColor: CodableColor(gridConfig.customColor),
            gridOpacity: gridConfig.opacity,
            grayscaleConversion: valueConfig.grayscaleConversion,
            valueLevels: valueConfig.levels,
            valueThresholds: valueConfig.thresholds,
            valueDistribution: valueConfig.distribution,
            valueQuantizationBias: valueConfig.quantizationBias,
            paletteSelectionEnabled: colorConfig.paletteSelectionEnabled,
            colorLimit: colorConfig.numShades,
            enabledPigmentIDs: colorConfig.enabledPigmentIDs.sorted(),
            paletteSpread: colorConfig.paletteSpread,
            colorQuantizationBias: colorConfig.quantizationBias,
            maxPigmentsPerMix: colorConfig.maxPigmentsPerMix,
            minConcentration: colorConfig.minConcentration,
            depthEnabled: depthConfig.enabled,
            foregroundCutoff: depthConfig.foregroundCutoff,
            backgroundCutoff: depthConfig.backgroundCutoff,
            depthEffectIntensity: depthConfig.effectIntensity,
            backgroundMode: depthConfig.backgroundMode,
            contourEnabled: contourConfig.enabled,
            contourLevels: contourConfig.levels,
            contourLineStyle: contourConfig.lineStyle,
            contourCustomColor: CodableColor(contourConfig.customColor),
            contourOpacity: contourConfig.opacity
        )
    }

    private func applyTransformationSnapshot(_ snapshot: TransformationSnapshot) {
        activeMode = snapshot.activeMode
        abstractionStrength = snapshot.abstractionStrength
        abstractionMethod = snapshot.abstractionMethod

        gridConfig = GridConfig(
            enabled: snapshot.gridEnabled,
            divisions: snapshot.gridDivisions,
            showDiagonals: snapshot.gridShowDiagonals,
            lineStyle: snapshot.gridLineStyle,
            customColor: snapshot.gridCustomColor.color,
            opacity: snapshot.gridOpacity
        )

        valueConfig = ValueConfig(
            grayscaleConversion: snapshot.grayscaleConversion,
            levels: snapshot.valueLevels,
            thresholds: snapshot.valueThresholds,
            distribution: snapshot.valueDistribution,
            quantizationBias: snapshot.valueQuantizationBias
        )

        colorConfig = ColorConfig(
            paletteSelectionEnabled: snapshot.paletteSelectionEnabled,
            numShades: snapshot.colorLimit,
            enabledPigmentIDs: Set(snapshot.enabledPigmentIDs),
            paletteSpread: snapshot.paletteSpread,
            quantizationBias: snapshot.colorQuantizationBias,
            maxPigmentsPerMix: snapshot.maxPigmentsPerMix,
            minConcentration: snapshot.minConcentration
        )

        depthConfig = DepthConfig(
            enabled: snapshot.depthEnabled,
            foregroundCutoff: snapshot.foregroundCutoff,
            backgroundCutoff: snapshot.backgroundCutoff,
            effectIntensity: snapshot.depthEffectIntensity,
            backgroundMode: snapshot.backgroundMode
        )

        contourConfig = ContourConfig(
            enabled: snapshot.contourEnabled,
            levels: snapshot.contourLevels,
            lineStyle: snapshot.contourLineStyle,
            customColor: snapshot.contourCustomColor.color,
            opacity: snapshot.contourOpacity
        )

        invalidateFocusIsolation(clearSelection: true)

        updatePreviousTransformSnapshot()

        if abstractionIsEnabled {
            applyAbstraction()
        } else {
            if depthConfig.enabled {
                computeDepthMap()
            }
            triggerProcessing()
        }
    }

    private func canonicalSelectionForCurrentSettings() -> TransformPresetSelection {
        let currentSnapshot = makeTransformationSnapshot()

        if let savedPresetID = matchingSavedPresetID(for: currentSnapshot) {
            return .saved(savedPresetID)
        }

        if currentSnapshot == Self.defaultTransformationSnapshot() {
            return .appDefault
        }

        if shouldShowPreviousSettingsOption {
            return .previous
        }

        return .appDefault
    }

    private func matchingSavedPresetID(for snapshot: TransformationSnapshot) -> UUID? {
        savedTransformPresets.first(where: { $0.snapshot == snapshot })?.id
    }

    private func updatePreviousTransformSnapshot() {
        previousTransformSnapshot = makeTransformationSnapshot()
        selectedTransformPresetSelection = canonicalSelectionForCurrentSettings()

        presetPersistenceTask?.cancel()
        presetPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            self.persistTransformPresetStore()
        }
    }

    private func loadTransformPresetStore() {
        guard let data = UserDefaults.standard.data(forKey: Self.transformPresetStoreKey) else {
            savedTransformPresets = []
            previousTransformSnapshot = nil
            return
        }

        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(TransformPresetStore.self, from: data),
              decoded.schemaVersion == 1
        else {
            savedTransformPresets = []
            previousTransformSnapshot = nil
            return
        }

        savedTransformPresets = decoded.savedPresets
        previousTransformSnapshot = decoded.previousSnapshot
    }

    private func persistTransformPresetStore() {
        let store = TransformPresetStore(
            schemaVersion: 1,
            savedPresets: savedTransformPresets,
            previousSnapshot: previousTransformSnapshot
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(store) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.transformPresetStoreKey)
    }

    private func restoreInitialTransformSnapshotSelection() {
        guard let previousTransformSnapshot else {
            selectedTransformPresetSelection = .appDefault
            return
        }

        if let matchingPresetID = matchingSavedPresetID(for: previousTransformSnapshot) {
            selectedTransformPresetSelection = .saved(matchingPresetID)
            applyTransformationSnapshot(previousTransformSnapshot)
            return
        }

        selectedTransformPresetSelection = .previous
        applyTransformationSnapshot(previousTransformSnapshot)
    }

    private static func defaultTransformationSnapshot() -> TransformationSnapshot {
        TransformationSnapshot(
            activeMode: .original,
            abstractionStrength: 0.5,
            abstractionMethod: .apisr,
            gridEnabled: false,
            gridDivisions: 4,
            gridShowDiagonals: false,
            gridLineStyle: .autoContrast,
            gridCustomColor: CodableColor(.white),
            gridOpacity: 0.7,
            grayscaleConversion: .none,
            valueLevels: 3,
            valueThresholds: defaultThresholds(for: 3),
            valueDistribution: .even,
            valueQuantizationBias: 0,
            paletteSelectionEnabled: false,
            colorLimit: 24,
            enabledPigmentIDs: SpectralDataStore.essentialPigments.map(\.id).sorted(),
            paletteSpread: 1,
            colorQuantizationBias: 0,
            maxPigmentsPerMix: 3,
            minConcentration: 0.02,
            depthEnabled: false,
            foregroundCutoff: 0.33,
            backgroundCutoff: 0.66,
            depthEffectIntensity: 0.5,
            backgroundMode: .none,
            contourEnabled: false,
            contourLevels: 5,
            contourLineStyle: .autoContrast,
            contourCustomColor: CodableColor(.white),
            contourOpacity: 0.7
        )
    }

    func exportCurrentImage() -> UIImage? {
        let base: UIImage?
        if activeMode == .original, let fullResolutionOriginalImage {
            base = fullResolutionOriginalImage
        } else {
            base = currentDisplayImage
        }
        guard let image = base else { return nil }
        var rendered = image
        if gridConfig.enabled {
            rendered = renderGridOnto(rendered)
        }
        if contourConfig.enabled && !contourSegments.isEmpty {
            rendered = renderContoursOnto(rendered)
        }
        return rendered
    }

    func exportCurrentImagePayload() -> ExportedImagePayload? {
        guard let image = exportCurrentImage() else { return nil }
        guard let imageData = image.pngData() else { return nil }
        return ExportedImagePayload(imageData: imageData, contentType: .png)
    }

    func currentSettingsDescription() -> String {
        let settings = makeExportSettingsSnapshot()
        let pigmentSummary = selectedPigmentDescription(
            for: settings.enabledPigmentIDs
        )
        let generatedPalette = makeGeneratedPaletteSnapshot()

        var lines = [
            "Application",
            makeExportSoftwareDescription(),
            "",
            "Mode",
            activeMode.label,
            "",
            "Background",
            "Enabled: \(displayDescription(for: settings.backgroundProcessingEnabled))",
            "Mode: \(settings.backgroundMode)",
            "Foreground Cutoff: \(formattedScalar(settings.foregroundDepthCutoff))",
            "Background Cutoff: \(formattedScalar(settings.backgroundDepthCutoff))",
            "Intensity: \(formattedScalar(settings.depthEffectIntensity))",
            "",
            "Simplification",
            "Method: \(settings.abstractionMethod)",
            "Strength: \(formattedScalar(settings.abstractionStrength))",
            "",
            "Grayscale Conversion",
            settings.grayscaleConversion,
            "",
            "Limit Colors / Values",
            "Values: \(settings.valueLevels)",
            "Value Bias: \(QuantizationBias.displayName(for: settings.valueQuantizationBias)) (\(formattedSignedScalar(settings.valueQuantizationBias)))",
            "Colors: \(settings.colorLimit)",
            "Color Bias: \(QuantizationBias.displayName(for: settings.colorQuantizationBias)) (\(formattedSignedScalar(settings.colorQuantizationBias)))",
            "",
            "Palette Selection",
            "Enabled: \(displayDescription(for: settings.paletteSelectionEnabled))",
            "Spread: \(formattedSignedScalar(settings.paletteSpread))",
            "Max Pigments per Mix: \(settings.maxPigmentsPerMix)",
            "Min Concentration: \(formattedScalar(Double(settings.minConcentration)))",
            "Pigments (\(settings.enabledPigmentIDs.count)): \(pigmentSummary)",
            "",
            "Contours",
            "Enabled: \(displayDescription(for: settings.contourEnabled))",
            "Levels: \(settings.contourLevels)",
            "Line Style: \(settings.contourLineStyle)",
            "Color: \(settings.contourCustomColor)",
            "Opacity: \(formattedScalar(settings.contourOpacity))",
            "",
            "Grid",
            "Enabled: \(displayDescription(for: settings.gridEnabled))",
            "Divisions: \(settings.gridDivisions)",
            "Diagonals: \(displayDescription(for: settings.gridShowDiagonals))",
            "Line Style: \(settings.gridLineStyle)",
            "Color: \(settings.gridCustomColor)",
            "Opacity: \(formattedScalar(settings.gridOpacity))"
        ]

        if !generatedPalette.isEmpty {
            lines.append("")
            lines.append("Generated Palette")
            lines.append(contentsOf: generatedPaletteDescription(from: generatedPalette))
        }

        return lines.joined(separator: "\n")
    }

    private func makeExportSoftwareDescription() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let gitRevision = makeExportGitRevision()
        return "RefPlane \(version) (\(build), git \(gitRevision))"
    }

    private func makeExportGitRevision() -> String {
        if let revision = Bundle.main.object(forInfoDictionaryKey: "RefPlaneGitRevision") as? String,
           !revision.isEmpty {
            return revision
        }

        guard let url = Bundle.main.url(
            forResource: "RefPlaneBuildMetadata",
            withExtension: "plist"
        ),
        let metadata = NSDictionary(contentsOf: url) as? [String: Any],
        let revision = metadata["gitRevision"] as? String,
        !revision.isEmpty
        else {
            return "unknown"
        }

        return revision
    }

    private func makeExportSettingsSnapshot() -> ExportSettingsMetadata {
        ExportSettingsMetadata(
            abstractionStrength: abstractionStrength,
            abstractionMethod: abstractionMethod.rawValue,
            grayscaleConversion: valueConfig.grayscaleConversion.rawValue,
            valueLevels: valueConfig.levels,
            valueQuantizationBias: valueConfig.quantizationBias,
            paletteSelectionEnabled: colorConfig.paletteSelectionEnabled,
            colorLimit: colorConfig.numShades,
            colorQuantizationBias: colorConfig.quantizationBias,
            paletteSpread: colorConfig.paletteSpread,
            maxPigmentsPerMix: colorConfig.maxPigmentsPerMix,
            minConcentration: colorConfig.minConcentration,
            enabledPigmentIDs: colorConfig.enabledPigmentIDs.sorted(),
            backgroundProcessingEnabled: depthConfig.enabled,
            backgroundMode: depthConfig.backgroundMode.rawValue,
            foregroundDepthCutoff: depthConfig.foregroundCutoff,
            backgroundDepthCutoff: depthConfig.backgroundCutoff,
            depthEffectIntensity: depthConfig.effectIntensity,
            gridEnabled: gridConfig.enabled,
            gridDivisions: gridConfig.divisions,
            gridShowDiagonals: gridConfig.showDiagonals,
            gridLineStyle: gridConfig.lineStyle.rawValue,
            gridCustomColor: metadataDescription(for: gridConfig.customColor),
            gridOpacity: gridConfig.opacity,
            contourEnabled: contourConfig.enabled,
            contourLevels: contourConfig.levels,
            contourLineStyle: contourConfig.lineStyle.rawValue,
            contourCustomColor: metadataDescription(for: contourConfig.customColor),
            contourOpacity: contourConfig.opacity
        )
    }

    private func metadataDescription(for color: Color) -> String {
        let resolvedColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return resolvedColor.description
        }

        return String(
            format: "#%02X%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()),
            Int((alpha * 255).rounded())
        )
    }

    private func selectedPigmentDescription(for pigmentIDs: [String]) -> String {
        let namesByID = Dictionary(
            uniqueKeysWithValues: SpectralDataStore.essentialPigments.map {
                ($0.id, $0.name)
            }
        )

        return pigmentIDs
            .map { pigmentID in
                if let name = namesByID[pigmentID] {
                    return "\(name) [\(pigmentID)]"
                }
                return pigmentID
            }
            .joined(separator: ", ")
    }

    private func makeGeneratedPaletteSnapshot() -> [ExportGeneratedPaletteMetadata] {
        guard !paletteColors.isEmpty else { return [] }

        var pixelCounts = [Int](repeating: 0, count: paletteColors.count)
        for band in processedPixelBands where pixelCounts.indices.contains(band) {
            pixelCounts[band] += 1
        }
        let totalPixels = max(1, pixelCounts.reduce(0, +))
        let clippedIndices = Set(clippedRecipeIndices)

        return paletteColors.indices.map { index in
            let recipe = pigmentRecipes.flatMap { recipes in
                recipes.indices.contains(index) ? recipes[index] : nil
            }

            return ExportGeneratedPaletteMetadata(
                index: index,
                color: metadataDescription(for: paletteColors[index]),
                pixelCount: pixelCounts[index],
                pixelShare: Double(pixelCounts[index]) / Double(totalPixels),
                recipe: recipe.map { exportGeneratedRecipeMetadata(from: $0) },
                clipped: clippedIndices.contains(index)
            )
        }
    }

    private func exportGeneratedRecipeMetadata(
        from recipe: PigmentRecipe
    ) -> ExportGeneratedRecipeMetadata {
        ExportGeneratedRecipeMetadata(
            deltaE: recipe.deltaE,
            components: recipe.components.map { component in
                ExportGeneratedRecipeComponentMetadata(
                    pigmentID: component.pigmentId,
                    pigmentName: component.pigmentName,
                    concentration: component.concentration
                )
            }
        )
    }

    private func generatedPaletteDescription(
        from entries: [ExportGeneratedPaletteMetadata]
    ) -> [String] {
        entries.map { entry in
            var parts = [
                "Swatch \(entry.index + 1)",
                entry.color,
                "\(formattedScalar(entry.pixelShare * 100))% (\(entry.pixelCount) px)"
            ]

            if let recipe = entry.recipe {
                let mix = recipe.components
                    .map { component in
                        "\(component.pigmentName) \(formattedScalar(Double(component.concentration * 100)))%"
                    }
                    .joined(separator: " + ")
                parts.append(mix)
                parts.append("Delta E \(formattedScalar(Double(recipe.deltaE)))")
                if entry.clipped {
                    parts.append("Clipped")
                }
            }

            return parts.joined(separator: " | ")
        }
    }

    private func displayDescription(for isEnabled: Bool) -> String {
        isEnabled ? "On" : "Off"
    }

    private func formattedScalar(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    private func formattedSignedScalar(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...3))
                .sign(strategy: .always(includingZero: false))
        )
    }

    private func renderGridOnto(_ image: UIImage) -> UIImage {
        let size = image.size
        let config = gridConfig
        let lineWidth = max(1.0, min(size.width, size.height) / 1000.0)
        let segments = GridLineColorResolver.resolvedSegments(
            config: config,
            image: image,
            segments: GridLineColorResolver.normalizedSegments(
                config: config,
                imageSize: size
            )
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.square)
            cg.clip(to: CGRect(origin: .zero, size: size))

            for resolvedSegment in segments {
                let mappedSegment = resolvedSegment.segment.mapped(
                    to: CGRect(origin: .zero, size: size)
                )
                let color = UIColor(resolvedSegment.color).withAlphaComponent(config.opacity)
                cg.setStrokeColor(color.cgColor)
                cg.move(to: mappedSegment.start)
                cg.addLine(to: mappedSegment.end)
                cg.strokePath()
            }
        }
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

    func toggleFocusedBand(_ band: Int) {
        var updatedBands = focusedBands
        if updatedBands.contains(band) {
            updatedBands.remove(band)
        } else {
            updatedBands.insert(band)
        }
        focusedBands = updatedBands
        refreshIsolatedProcessedImage()
    }

    func toggleFocusedBand(atNormalizedPoint point: CGPoint) {
        guard let band = band(atNormalizedPoint: point) else { return }
        toggleFocusedBand(band)
    }

    func toggleIsolatedBand(_ band: Int) {
        toggleFocusedBand(band)
    }

    func toggleIsolatedBand(atNormalizedPoint point: CGPoint) {
        toggleFocusedBand(atNormalizedPoint: point)
    }

    func clearFocusedBands() {
        guard !focusedBands.isEmpty else { return }
        focusedBands = []
        refreshIsolatedProcessedImage()
    }

    func clearIsolatedBandSelection() {
        clearFocusedBands()
    }

    private func refreshIsolatedProcessedImage() {
        invalidateFocusIsolation(clearSelection: false)

        guard activeMode == .value || activeMode == .color,
              !focusedBands.isEmpty,
              let processedImage else {
            return
        }

        let pixelBands = processedPixelBands
        let selectedBands = focusedBands

        focusIsolationTask = Task { @MainActor [weak self] in
            let isolated = await BandIsolationRenderer.isolateAsync(
                image: processedImage,
                pixelBands: pixelBands,
                selectedBands: selectedBands
            )
            try? Task.checkCancellation()
            guard !Task.isCancelled, let self else { return }

            self.isolatedProcessedImage = isolated
        }
    }

    private func invalidateFocusIsolation(clearSelection: Bool) {
        focusIsolationTask?.cancel()
        focusIsolationTask = nil
        isolatedProcessedImage = nil
        if clearSelection {
            focusedBands = []
        }
    }

    // MARK: - Depth processing

    func computeDepthMap() {
        depthTask?.cancel()
        depthTask = nil

        guard let source = displayBaseImage else {
            depthProcessedImage = nil
            return
        }

        guard depthConfig.enabled else {
            depthProcessedImage = nil
            return
        }


        if let embedded = embeddedDepthMap {
            let resized = DepthEstimator.resize(embedded, toMatch: source)
            let range = DepthEstimator.depthRange(from: resized)
            if shouldUseEmbeddedDepth(resized, range: range) {
                let isFirstCompute = depthMap == nil
                depthMap = resized
                depthRange = range
                depthSource = .embedded
                syncDepthCutoffs(to: range, resetToDefaults: isFirstCompute)
                logDepthDiagnostics(event: "embedded-depth-selected", depth: resized)
                applyDepthEffects()
                recomputeContours()
                return
            }

            AppState.depthLogger.warning(
                "Embedded depth rejected as sparse/flat (rangeSpan=\((range.upperBound - range.lowerBound), format: .fixed(precision: 6))); falling back to estimated depth"
            )
            embeddedDepthMap = nil
        }

        isProcessing = true
        processingLabel = "Estimating depth…"
        processingIsIndeterminate = true

        depthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.depthMapOperation(source)
                try Task.checkCancellation()

                let range = DepthEstimator.depthRange(from: result)

                let isFirstCompute = self.depthMap == nil
                self.depthMap = result
                self.depthRange = range
                self.depthSource = .estimated
                // Keep cutoffs aligned with the latest measured range.
                self.syncDepthCutoffs(to: range, resetToDefaults: isFirstCompute)
                self.logDepthDiagnostics(event: "estimated-depth-selected", depth: result)
                self.processingIsIndeterminate = false
                self.processingLabel = "Processing…"
                self.isProcessing = false
                self.applyDepthEffects()
                self.recomputeContours()
            } catch is CancellationError {
                // superseded
            } catch {
                self.isProcessing = false
                self.processingIsIndeterminate = false
                self.processingLabel = "Processing…"
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func applyDepthEffects() {
        depthEffectTask?.cancel()

        guard depthConfig.enabled, let depth = depthMap else {
            depthProcessedImage = nil
            return
        }

        guard let sourceImage = depthEffectSourceImage() else {
            depthProcessedImage = nil
            return
        }

        let config = depthConfig


        isProcessing = true
        processingLabel = "Applying depth…"
        processingIsIndeterminate = true

        depthEffectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Let the synchronous operation run on a background thread
            let result = await Task.detached(priority: .userInitiated) {
                self.depthEffectOperation(sourceImage, depth, config)
            }.value
            
            try? Task.checkCancellation()
            guard !Task.isCancelled else { return }
            
            self.isProcessing = false
            self.depthProcessedImage = result
            self.processingIsIndeterminate = false
            self.processingLabel = "Processing…"
        }
    }

    private func depthEffectSourceImage() -> UIImage? {
        if activeMode == .original {
            return displayBaseImage
        }

        return isolatedProcessedImage ?? processedImage ?? displayBaseImage
    }

    func resetDepthProcessing() {
        depthTask?.cancel()
        depthEffectTask?.cancel()
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()
        depthMap = nil
        depthProcessedImage = nil
        isEditingDepthThreshold = false
        depthSliderActive = false
        depthThresholdPreview = nil
        cachedDepthTexture = nil
        cachedSourceTexture = nil
        depthRange = 0...1
        contourSegments = []
    }

    func updateBackgroundDepthCutoff(_ newValue: Double) {
        guard newValue != depthConfig.backgroundCutoff else {
            return
        }
        depthConfig.backgroundCutoff = newValue
        depthConfig.foregroundCutoff = min(depthConfig.foregroundCutoff, newValue)
        refreshDepthThresholdOutput()
    }

    /// Regenerate the depth-threshold preview image showing which pixels
    /// fall into the background zone. Called while the user drags a cutoff slider.
    func updateDepthThresholdPreview() {
        guard let depth = depthMap, let source = depthEffectSourceImage() else {
            isEditingDepthThreshold = false
            depthThresholdPreview = nil
            cachedDepthTexture = nil
            cachedSourceTexture = nil
            return
        }
        let bg = depthConfig.backgroundCutoff
        let result = DepthProcessor.thresholdPreview(
            sourceImage: source,
            depthMap: depth,
            backgroundCutoff: bg,
            cachedDepthTexture: cachedDepthTexture,
            cachedSourceTexture: cachedSourceTexture
        )
        isEditingDepthThreshold = true
        depthThresholdPreview = result.image
        cachedDepthTexture = result.cachedDepthTexture
        cachedSourceTexture = result.cachedSourceTexture
        if let coverage = backgroundCoverage(in: depth, cutoff: bg) {
            AppState.depthLogger.debug(
                "Depth slider preview cutoff=\(bg, format: .fixed(precision: 4)) backgroundCoveragePct=\((coverage * 100.0), format: .fixed(precision: 2))"
            )
        }
    }

    /// Schedule auto-dismiss of the depth threshold preview as a safety net
    /// in case onEditingChanged(false) doesn't fire.
    func schedulePreviewDismissSafetyNet() {
        depthPreviewDismissTask?.cancel()
        depthPreviewDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s safety net
            guard !Task.isCancelled, let self else { return }
            guard !self.depthSliderActive else { return }
            self.dismissDepthThresholdPreview()
        }
    }

    /// Dismiss the depth threshold preview and apply the current depth effects.
    func dismissDepthThresholdPreview() {
        depthPreviewDismissTask?.cancel()
        depthSliderActive = false
        guard isEditingDepthThreshold else {
            return
        }
        isEditingDepthThreshold = false
        depthThresholdPreview = nil
        cachedDepthTexture = nil
        cachedSourceTexture = nil
        applyDepthEffects()
        recomputeContours()
    }

    private func refreshDepthThresholdOutput() {
        if depthSliderActive {
            updateDepthThresholdPreview()
        } else if isEditingDepthThreshold || depthThresholdPreview != nil {
            dismissDepthThresholdPreview()
        } else {
            applyDepthEffects()
            recomputeContours()
        }
    }

    private func logDepthDiagnostics(event: String, depth: UIImage) {
        let range = depthRange
        let sourceSize = displayBaseImage?.size ?? .zero
        let depthSize = depth.size
        let coverage = backgroundCoverage(in: depth, cutoff: depthConfig.backgroundCutoff)
        let pixels = grayscalePixels(from: depth)
        let globalHistogram = depthHistogramSummary(from: pixels, bins: 16, domain: 0.0...1.0)
        let localHistogram = depthHistogramSummary(from: pixels, bins: 24, domain: range)
        let percentiles = depthPercentileSummary(from: pixels)
        let nonZeroSummary = nonZeroDepthSummary(from: pixels)
        let tailSummary = tailOccupancySummary(from: pixels)
        let foregroundCutoff = depthConfig.foregroundCutoff
        let backgroundCutoff = depthConfig.backgroundCutoff
        AppState.depthLogger.info(
            "\(event, privacy: .public) source=\(Int(sourceSize.width))x\(Int(sourceSize.height)) depth=\(Int(depthSize.width))x\(Int(depthSize.height)) depthRange=[\(range.lowerBound, format: .fixed(precision: 6)), \(range.upperBound, format: .fixed(precision: 6))] fg=\(foregroundCutoff, format: .fixed(precision: 6)) bg=\(backgroundCutoff, format: .fixed(precision: 6)) bgCoverage=\(coverage ?? -1, format: .fixed(precision: 4)) nonZero=\(nonZeroSummary, privacy: .public) tail=\(tailSummary, privacy: .public) histGlobal=\(globalHistogram, privacy: .public) histLocal=\(localHistogram, privacy: .public) pct=\(percentiles, privacy: .public)"
        )
    }

    private func syncDepthCutoffs(to range: ClosedRange<Double>, resetToDefaults: Bool) {
        let lower = range.lowerBound
        let upper = range.upperBound
        let span = max(upper - lower, 1.0 / 255.0)

        if resetToDefaults {
            depthConfig.foregroundCutoff = lower + span / 3.0
            depthConfig.backgroundCutoff = lower + span * 2.0 / 3.0
            return
        }

        let clampedForeground = min(upper, max(lower, depthConfig.foregroundCutoff))
        let clampedBackground = min(upper, max(lower, depthConfig.backgroundCutoff))
        depthConfig.foregroundCutoff = min(clampedForeground, clampedBackground)
        depthConfig.backgroundCutoff = max(clampedForeground, clampedBackground)
    }

    private func backgroundCoverage(in depthImage: UIImage, cutoff: Double) -> Double? {
        guard let pixels = grayscalePixels(from: depthImage) else {
            return nil
        }

        let threshold = UInt8(max(0, min(255, Int((cutoff * 255.0).rounded()))))
        var count = 0
        for pixel in pixels where pixel >= threshold {
            count += 1
        }
        return Double(count) / Double(pixels.count)
    }

    private func depthHistogramSummary(
        from pixels: [UInt8]?,
        bins: Int,
        domain: ClosedRange<Double>
    ) -> String {
        guard bins > 0, let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        let lo = max(0.0, min(1.0, domain.lowerBound))
        let hi = max(lo + (1.0 / 255.0), min(1.0, domain.upperBound))
        let span = hi - lo

        var counts = [Int](repeating: 0, count: bins)
        for pixel in pixels {
            let value = Double(pixel) / 255.0
            if value < lo || value > hi {
                continue
            }
            let normalized = (value - lo) / span
            let index = min(bins - 1, max(0, Int((normalized * Double(bins)).rounded(.down))))
            counts[index] += 1
        }

        let total = Double(pixels.count)
        let bucketDescriptions = counts.enumerated().map { idx, count -> String in
            let bucketLo = lo + (Double(idx) / Double(bins)) * span
            let bucketHi = lo + (Double(idx + 1) / Double(bins)) * span
            let pct = (Double(count) / total) * 100.0
            return String(format: "%.3f-%.3f:%d(%.3f%%)", bucketLo, bucketHi, count, pct)
        }

        return "[\(bucketDescriptions.joined(separator: ", "))]"
    }

    private func depthPercentileSummary(from pixels: [UInt8]?) -> String {
        guard let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        var counts = [Int](repeating: 0, count: 256)
        for pixel in pixels {
            counts[Int(pixel)] += 1
        }

        let total = pixels.count
        func percentile(_ p: Double) -> Double {
            let target = Int((Double(total - 1) * p).rounded())
            var cumulative = 0
            for (value, count) in counts.enumerated() {
                cumulative += count
                if cumulative > target {
                    return Double(value) / 255.0
                }
            }
            return 1.0
        }

        let p10 = percentile(0.10)
        let p50 = percentile(0.50)
        let p90 = percentile(0.90)
        let p99 = percentile(0.99)
        let p999 = percentile(0.999)
        return String(format: "p10=%.4f,p50=%.4f,p90=%.4f,p99=%.4f,p99.9=%.4f", p10, p50, p90, p99, p999)
    }

    private func tailOccupancySummary(from pixels: [UInt8]?) -> String {
        guard let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        let total = Double(pixels.count)
        let above98 = pixels.reduce(into: 0) { count, pixel in
            if pixel >= 250 { // >= 0.9804
                count += 1
            }
        }
        let above995 = pixels.reduce(into: 0) { count, pixel in
            if pixel >= 254 { // >= 0.9961
                count += 1
            }
        }

        return String(
            format: ">=0.98:%d(%.3f%%),>=0.996:%d(%.3f%%)",
            above98,
            (Double(above98) / total) * 100.0,
            above995,
            (Double(above995) / total) * 100.0
        )
    }

    private func shouldUseEmbeddedDepth(_ depthImage: UIImage, range: ClosedRange<Double>) -> Bool {
        guard let pixels = grayscalePixels(from: depthImage), !pixels.isEmpty else {
            return false
        }

        let nonZeroCount = pixels.reduce(into: 0) { partialResult, pixel in
            if pixel > 0 {
                partialResult += 1
            }
        }

        let nonZeroRatio = Double(nonZeroCount) / Double(pixels.count)
        let span = range.upperBound - range.lowerBound

        // Treat maps as invalid when almost all pixels are zero or the span is
        // effectively quantized to a near-flat signal.
        let minNonZeroRatio = 0.001   // 0.1%
        let minSpan = 2.0 / 255.0

        if nonZeroRatio < minNonZeroRatio {
            AppState.depthLogger.warning(
                "Embedded depth nonZeroRatio too low: \(nonZeroRatio, format: .fixed(precision: 6))"
            )
            return false
        }

        if span < minSpan {
            AppState.depthLogger.warning(
                "Embedded depth span too low: \(span, format: .fixed(precision: 6))"
            )
            return false
        }

        return true
    }

    private func nonZeroDepthSummary(from pixels: [UInt8]?) -> String {
        guard let pixels, !pixels.isEmpty else {
            return "unavailable"
        }

        var counts = [Int](repeating: 0, count: 256)
        for pixel in pixels {
            counts[Int(pixel)] += 1
        }

        let total = pixels.count
        let nonZeroCount = total - counts[0]
        if nonZeroCount == 0 {
            return "0/\(total) (0.000%)"
        }

        let minNonZeroByte = counts.enumerated().first(where: { $0.offset > 0 && $0.element > 0 })?.offset ?? 1
        var maxNonZeroByte = 255
        while maxNonZeroByte > 0 && counts[maxNonZeroByte] == 0 {
            maxNonZeroByte -= 1
        }

        let topLevels = counts.enumerated()
            .filter { $0.offset > 0 && $0.element > 0 }
            .sorted { lhs, rhs in
                if lhs.element == rhs.element {
                    return lhs.offset < rhs.offset
                }
                return lhs.element > rhs.element
            }
            .prefix(6)
            .map { "\($0.offset):\($0.element)" }
            .joined(separator: "|")

        let pct = (Double(nonZeroCount) / Double(total)) * 100.0
        return String(
            format: "%d/%d (%.3f%%) minNZ=%.4f maxNZ=%.4f topNZ=[%@]",
            nonZeroCount,
            total,
            pct,
            Double(minNonZeroByte) / 255.0,
            Double(maxNonZeroByte) / 255.0,
            topLevels
        )
    }

    private func grayscalePixels(from depthImage: UIImage) -> [UInt8]? {
        guard let cgImage = depthImage.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    // MARK: - Contour line generation

    func recomputeContours() {
        contourTask?.cancel()
        guard contourConfig.enabled, let depth = depthMap else {
            contourSegments = []
            return
        }
        let cfg = contourConfig
        let depthCfg = depthConfig
        let range = depthRange
        contourTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let segs = await Task.detached(priority: .userInitiated) {
                ContourGenerator.generateSegments(
                    depthMap: depth,
                    levels: cfg.levels,
                    depthRange: range,
                    backgroundCutoff: depthCfg.backgroundCutoff
                )
            }.value
            
            try? Task.checkCancellation()
            guard !Task.isCancelled else { return }
            self.contourSegments = segs
        }
    }

    private func renderContoursOnto(_ image: UIImage) -> UIImage {
        let size = image.size
        let config = contourConfig
        let segments = contourSegments
        let lineWidth = max(1.0, min(size.width, size.height) / 1000.0)

        let resolved = ContourLineColorResolver.resolvedSegments(
            config: config,
            image: image,
            segments: segments
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)
            cg.clip(to: CGRect(origin: .zero, size: size))

            for resolvedSegment in resolved {
                let mappedSegment = resolvedSegment.segment.mapped(
                    to: CGRect(origin: .zero, size: size)
                )
                let color = UIColor(resolvedSegment.color).withAlphaComponent(config.opacity)
                cg.setStrokeColor(color.cgColor)
                cg.move(to: mappedSegment.start)
                cg.addLine(to: mappedSegment.end)
                cg.strokePath()
            }
        }
    }

}

private struct ExportSettingsMetadata: Encodable {
    var abstractionStrength: Double
    var abstractionMethod: String
    var grayscaleConversion: String
    var valueLevels: Int
    var valueQuantizationBias: Double
    var paletteSelectionEnabled: Bool
    var colorLimit: Int
    var colorQuantizationBias: Double
    var paletteSpread: Double
    var maxPigmentsPerMix: Int
    var minConcentration: Float
    var enabledPigmentIDs: [String]
    var backgroundProcessingEnabled: Bool
    var backgroundMode: String
    var foregroundDepthCutoff: Double
    var backgroundDepthCutoff: Double
    var depthEffectIntensity: Double
    var gridEnabled: Bool
    var gridDivisions: Int
    var gridShowDiagonals: Bool
    var gridLineStyle: String
    var gridCustomColor: String
    var gridOpacity: Double
    var contourEnabled: Bool
    var contourLevels: Int
    var contourLineStyle: String
    var contourCustomColor: String
    var contourOpacity: Double
}

private struct ExportGeneratedPaletteMetadata: Encodable {
    var index: Int
    var color: String
    var pixelCount: Int
    var pixelShare: Double
    var recipe: ExportGeneratedRecipeMetadata?
    var clipped: Bool
}

private struct ExportGeneratedRecipeMetadata: Encodable {
    var deltaE: Float
    var components: [ExportGeneratedRecipeComponentMetadata]
}

private struct ExportGeneratedRecipeComponentMetadata: Encodable {
    var pigmentID: String
    var pigmentName: String
    var concentration: Float
}
