import ImageIO
import SwiftUI
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
class AppState {
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
        var kuwaharaStrength: Double
        var postSimplificationStrength: Double

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

        // Backward-compatible decoding: older presets won't have postSimplificationStrength.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            activeMode = try c.decode(RefPlaneMode.self, forKey: .activeMode)
            abstractionStrength = try c.decode(Double.self, forKey: .abstractionStrength)
            abstractionMethod = try c.decode(AbstractionMethod.self, forKey: .abstractionMethod)
            kuwaharaStrength = try c.decode(Double.self, forKey: .kuwaharaStrength)
            postSimplificationStrength = try c.decodeIfPresent(Double.self, forKey: .postSimplificationStrength) ?? 0
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
            kuwaharaStrength: Double,
            postSimplificationStrength: Double,
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
            self.kuwaharaStrength = kuwaharaStrength
            self.postSimplificationStrength = postSimplificationStrength
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

    /// Apply the Kuwahara post-filter. Returns the filtered image, or nil on failure.
    typealias KuwaharaOperation = @Sendable (UIImage, Int) async -> UIImage?

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
    var isolatedBand: Int? = nil
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
    /// True while the user's finger is actively on a depth cutoff slider.
    @ObservationIgnored var depthSliderActive: Bool = false
    /// Abstraction strength 0–1. `0` disables abstraction; positive values map
    /// to the existing downscale-based abstraction range.
    var abstractionStrength: Double = 0.5
    var abstractionMethod: AbstractionMethod = .apisr
    /// Kuwahara post-filter strength 0–1. `0` disables the filter; positive
    /// values map to a neighbourhood radius of 1...16 applied after the SR model.
    var kuwaharaStrength: Double = 0
    /// Post-simplification strength 0–1. When positive, runs a second SR-based
    /// abstraction pass on the quantised (mode-processed) output to smooth edges.
    var postSimplificationStrength: Double = 0

    // Abstracted image (after upscale/denoise)
    var abstractedImage: UIImage? = nil
    /// Kuwahara-filtered image applied on top of the abstracted (or source) image.
    var kuwaharaFilteredImage: UIImage? = nil
    /// Post-simplified image: the processedImage after a second abstraction pass.
    var postSimplifiedImage: UIImage? = nil

    @ObservationIgnored private var processingTask: Task<Void, Never>? = nil
    @ObservationIgnored private var processingDebounceTask: Task<Void, Never>? = nil
    @ObservationIgnored private let processOperation: ProcessOperation
    /// Incremented on every triggerProcessing() call; lets each task know if it is still current.
    @ObservationIgnored private var processingGeneration: Int = 0

    @ObservationIgnored private let abstractionOperation: AbstractionOperation
    @ObservationIgnored private var abstractionTask: Task<Void, Never>? = nil
    @ObservationIgnored private var abstractionGeneration: Int = 0

    @ObservationIgnored private let kuwaharaOperation: KuwaharaOperation
    @ObservationIgnored private var kuwaharaTask: Task<Void, Never>? = nil

    @ObservationIgnored private var postSimplificationTask: Task<Void, Never>? = nil
    @ObservationIgnored private var postSimplificationGeneration: Int = 0

    @ObservationIgnored private var loadingTask: Task<Void, Never>? = nil
    @ObservationIgnored private(set) var sourceImageMetadata: SourceImageMetadata = .empty
    private var processedPixelBands: [Int] = []

    @ObservationIgnored private let depthMapOperation: DepthMapOperation
    @ObservationIgnored private let depthEffectOperation: DepthEffectOperation
    @ObservationIgnored private var depthTask: Task<Void, Never>? = nil
    @ObservationIgnored private var depthEffectTask: Task<Void, Never>? = nil
    @ObservationIgnored private var depthPreviewDismissTask: Task<Void, Never>? = nil
    @ObservationIgnored private var depthGeneration: Int = 0
    @ObservationIgnored private var depthEffectGeneration: Int = 0

    @ObservationIgnored private var contourTask: Task<Void, Never>? = nil
    @ObservationIgnored private var contourGeneration: Int = 0
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol? = nil
    @ObservationIgnored private var presetPersistenceTask: Task<Void, Never>? = nil

    @ObservationIgnored private static let transformPresetStoreKey = "AppState.transformPresetStore.v1"

    var abstractionIsEnabled: Bool {
        abstractionStrength > 0
    }

    var postSimplificationIsEnabled: Bool {
        postSimplificationStrength > 0
    }

    /// Kuwahara neighbourhood radius derived from `postSimplificationStrength`.
    /// Returns 0 when the filter is off, and a value clamped to 1...16 otherwise.
    var postSimplificationRadius: Int {
        guard postSimplificationStrength > 0 else { return 0 }
        return min(max(Int((postSimplificationStrength * 16).rounded()), 1), 16)
    }

    /// Kuwahara neighbourhood radius derived from `kuwaharaStrength`.
    /// Returns 0 when the filter is off, and a value clamped to 1...16 otherwise.
    var kuwaharaRadius: Int {
        guard kuwaharaStrength > 0 else { return 0 }
        return min(max(Int((kuwaharaStrength * 16).rounded()), 1), 16)
    }

    var availableAbstractionMethods: [AbstractionMethod] {
        AbstractionMethod.allCases.filter { method in
            switch method.processingKind {
            case .superResolution4x, .fullImageModel:
                guard let name = method.modelBundleName else { return false }
                return Bundle.main.url(forResource: name, withExtension: "mlmodelc") != nil
                    || Bundle.main.url(forResource: name, withExtension: "mlpackage") != nil
                    || Bundle.main.url(forResource: name, withExtension: "mlmodel") != nil
            case .metalShader:
                return MetalContext.shared != nil
            }
        }
    }

    init(
        processOperation: ProcessOperation? = nil,
        abstractionOperation: AbstractionOperation? = nil,
        kuwaharaOperation: KuwaharaOperation? = nil,
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
        self.kuwaharaOperation = kuwaharaOperation ?? { image, radius in
            guard let ctx = MetalContext.shared, let origCG = image.cgImage else { return nil }
            let origW = origCG.width
            let origH = origCG.height

            // The radius is defined relative to a ~600 px reference image.
            // Raw CGImages on Retina devices are often 2–4× larger in each dimension
            // (e.g. 4032 px at 3× scale), making the effect invisible at the raw
            // pixel level.  Downsample to ≤600 px on the longest side, apply the
            // filter there, then upscale back so downstream processing sees the
            // original pixel dimensions.
            let maxWorkPx = 600
            let longestSide = max(origW, origH)

            let workCG: CGImage
            if longestSide > maxWorkPx {
                let s    = Double(maxWorkPx) / Double(longestSide)
                let workW = max(1, Int((Double(origW) * s).rounded()))
                let workH = max(1, Int((Double(origH) * s).rounded()))
                let fmt  = UIGraphicsImageRendererFormat.default()
                fmt.scale = 1.0
                let small = UIGraphicsImageRenderer(size: CGSize(width: workW, height: workH), format: fmt)
                    .image { _ in image.draw(in: CGRect(x: 0, y: 0, width: workW, height: workH)) }
                guard let cg = small.cgImage else { return nil }
                workCG = cg
            } else {
                workCG = origCG
            }

            guard let filtered = ctx.anisotropicKuwahara(workCG, radius: radius) else { return nil }

            // Upscale back to original pixel dimensions if we downsampled.
            guard workCG.width != origW || workCG.height != origH else { return filtered }
            let fmt = UIGraphicsImageRendererFormat.default()
            fmt.scale = 1.0
            return UIGraphicsImageRenderer(size: CGSize(width: origW, height: origH), format: fmt)
                .image { _ in filtered.draw(in: CGRect(x: 0, y: 0, width: origW, height: origH)) }
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
        kuwaharaTask?.cancel()
        postSimplificationTask?.cancel()
        depthTask?.cancel()
        depthEffectTask?.cancel()
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()
        presetPersistenceTask?.cancel()
    }

    var displayBaseImage: UIImage? { kuwaharaFilteredImage ?? abstractedImage ?? sourceImage }

    var currentDisplayImage: UIImage? {
        // While adjusting depth thresholds, show the threshold preview
        if isEditingDepthThreshold, let preview = depthThresholdPreview {
            return preview
        }
        let modeResult = activeMode == .original
            ? displayBaseImage
            : (isolatedProcessedImage ?? postSimplifiedImage ?? processedImage ?? displayBaseImage)
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

    func loadImage(_ image: UIImage) {
        loadImage(ImportedImagePayload(image: image))
    }

    func loadImage(_ payload: ImportedImagePayload) {
        let image = payload.image

        // Cancel any in-flight work before starting fresh.
        loadingTask?.cancel()
        processingDebounceTask?.cancel()
        processingTask?.cancel()
        abstractionTask?.cancel()
        kuwaharaTask?.cancel()
        postSimplificationTask?.cancel()
        depthTask?.cancel()
        depthEffectTask?.cancel()
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()

        // Invalidate stale completions in case any task ignores cancellation.
        processingGeneration += 1
        abstractionGeneration += 1
        postSimplificationGeneration += 1
        depthGeneration += 1
        depthEffectGeneration += 1
        contourGeneration += 1

        // Show the picked image immediately, then swap in the scaled version
        // once preprocessing finishes so the canvas never blanks out.
        sourceImageMetadata        = payload.metadata
        fullResolutionOriginalImage   = image
        originalImage             = image
        sourceImage               = image
        abstractedImage           = nil
        kuwaharaFilteredImage     = nil
        postSimplifiedImage       = nil
        processedImage            = nil
        isolatedProcessedImage    = nil
        depthMap                  = nil
        depthProcessedImage       = nil
        depthThresholdPreview     = nil
        cachedDepthTexture        = nil
        depthRange                = 0...1
        contourSegments           = []
        processedPixelBands       = []
        paletteColors             = []
        paletteBands              = []
        pigmentRecipes            = nil
        selectedTubes             = []
        clippedRecipeIndices      = []
        isolatedBand              = nil
        errorMessage              = nil
        isProcessing              = true
        isSimplifying             = true
        processingProgress        = 0
        processingLabel           = "Loading…"
        processingIsIndeterminate = true

        loadingTask = Task {
            let maxSize: CGFloat = 1600
            let scaled = await image.scaledDownAsync(toMaxDimension: maxSize)
            guard !Task.isCancelled else { return }
            originalImage             = scaled
            sourceImage               = scaled
            if abstractionIsEnabled {
                applyAbstraction()
            } else if kuwaharaStrength > 0 {
                processingLabel           = "Processing…"
                processingIsIndeterminate = false
                applyKuwahara()
            } else {
                isSimplifying             = false
                processingLabel           = "Processing…"
                processingIsIndeterminate = false
                triggerProcessing()
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
            isolatedProcessedImage = nil
            postSimplifiedImage = nil
            processedPixelBands = []
            isProcessing = false
            processingProgress = 0
            if depthConfig.enabled && depthMap != nil {
                applyDepthEffects()
            }
            return
        }

        // Set processing state synchronously so the UI shows the spinner
        // on the very first SwiftUI render after the mode change.
        isProcessing = true
        processingProgress = 0

        processingGeneration += 1
        let myGeneration = processingGeneration
        let mode = activeMode

        processingTask = Task {
            do {
                let result = try await processOperation(
                    source,
                    mode,
                    valueConfig,
                    colorConfig,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.processingProgress = p }
                    }
                )
                try Task.checkCancellation()

                try Task.checkCancellation()
                await MainActor.run {
                    self.processedImage      = result.image
                    self.processedPixelBands = result.pixelBands
                    self.paletteColors       = result.palette
                    self.paletteBands        = result.paletteBands
                    self.pigmentRecipes      = result.pigmentRecipes
                    self.selectedTubes       = result.selectedTubes
                    self.clippedRecipeIndices = result.clippedRecipeIndices
                    self.processingProgress  = 1
                    self.refreshIsolatedProcessedImage()
                    if self.postSimplificationIsEnabled {
                        self.applyPostSimplification()
                    } else {
                        self.postSimplifiedImage = nil
                    }
                    if self.depthConfig.enabled && self.depthMap != nil {
                        self.applyDepthEffects()
                    }
                }
            } catch is CancellationError {
                // Mode switched or new image loaded — new task will update state
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
            // Only clear the flag if we are still the most-recent processing task
            // and depth-effect rendering hasn't taken ownership of the indicator.
            await MainActor.run {
                if self.processingGeneration == myGeneration &&
                   !(self.depthConfig.enabled && self.depthMap != nil) {
                    self.isProcessing = false
                }
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
        isolatedBand = nil
        processedImage = nil
        isolatedProcessedImage = nil
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
            kuwaharaStrength: kuwaharaStrength,
            postSimplificationStrength: postSimplificationStrength,
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
        kuwaharaStrength = snapshot.kuwaharaStrength
        postSimplificationStrength = snapshot.postSimplificationStrength

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

        isolatedBand = nil
        isolatedProcessedImage = nil

        updatePreviousTransformSnapshot()

        if abstractionIsEnabled {
            applyAbstraction()
        } else if kuwaharaStrength > 0 {
            applyKuwahara()
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
            kuwaharaStrength: 0,
            postSimplificationStrength: 0,
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
            paletteSpread: 0,
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
        let contentType = preferredExportContentType(for: image)

        if let encoded = encodeExportImage(image, as: contentType) {
            return ExportedImagePayload(imageData: encoded, contentType: contentType)
        }

        guard contentType != .png,
              let fallbackData = encodeExportImage(image, as: .png)
        else { return nil }

        return ExportedImagePayload(imageData: fallbackData, contentType: .png)
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
            "Kuwahara: \(formattedScalar(settings.kuwaharaStrength))",
            "Post-simplify: \(formattedScalar(settings.postSimplificationStrength))",
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

    private func preferredExportContentType(for image: UIImage) -> UTType {
        guard let typeIdentifier = sourceImageMetadata.uniformTypeIdentifier,
              let sourceType = UTType(typeIdentifier),
              sourceType.conforms(to: .image),
              Self.supportedExportTypeIdentifiers.contains(sourceType.identifier)
        else {
            return .png
        }

        if imageContainsAlpha(image), !Self.alphaCapableExportTypes.contains(sourceType.identifier) {
            return .png
        }

        return sourceType
    }

    private static let supportedExportTypeIdentifiers: Set<String> = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return Set(identifiers)
    }()

    private static let alphaCapableExportTypes: Set<String> = [
        UTType.png.identifier,
        UTType.heic.identifier,
        UTType.heif.identifier,
        UTType.tiff.identifier,
        "public.heics"
    ]

    private func encodeExportImage(_ image: UIImage, as contentType: UTType) -> Data? {
        let normalizedImage = normalizedImageForExport(image)
        guard let cgImage = normalizedImage.cgImage else { return nil }

        let properties = exportProperties(
            for: normalizedImage,
            contentType: contentType
        )
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            contentType.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func normalizedImageForExport(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.cgImage != nil {
            return image
        }

        let pixelSize = exportPixelSize(for: image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }

    private func exportProperties(
        for image: UIImage,
        contentType: UTType
    ) -> [String: Any] {
        let pixelSize = exportPixelSize(for: image)
        let pixelWidth = Int(pixelSize.width.rounded())
        let pixelHeight = Int(pixelSize.height.rounded())
        let provenanceJSON = makeExportProvenanceJSON()
        let softwareDescription = makeExportSoftwareDescription()

        var properties = sourceImageMetadata.properties
        properties[kCGImagePropertyPixelWidth as String] = pixelWidth
        properties[kCGImagePropertyPixelHeight as String] = pixelHeight
        properties[kCGImagePropertyOrientation as String] = CGImagePropertyOrientation.up.rawValue

        var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        tiff[kCGImagePropertyTIFFSoftware as String] = softwareDescription
        tiff[kCGImagePropertyTIFFImageDescription as String] = provenanceJSON
        tiff[kCGImagePropertyTIFFOrientation as String] = CGImagePropertyOrientation.up.rawValue
        properties[kCGImagePropertyTIFFDictionary as String] = tiff

        var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension as String] = pixelWidth
        exif[kCGImagePropertyExifPixelYDimension as String] = pixelHeight
        exif[kCGImagePropertyExifUserComment as String] = provenanceJSON
        properties[kCGImagePropertyExifDictionary as String] = exif

        if contentType.conforms(to: .png) {
            var png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any] ?? [:]
            png[kCGImagePropertyPNGSoftware as String] = softwareDescription
            png[kCGImagePropertyPNGDescription as String] = provenanceJSON
            properties[kCGImagePropertyPNGDictionary as String] = png
        }

        if contentType != .png {
            properties[kCGImageDestinationLossyCompressionQuality as String] = 1.0
        }

        return properties
    }

    private func makeExportSoftwareDescription() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let gitRevision = makeExportGitRevision()
        return "RefPlane \(version) (\(build), git \(gitRevision))"
    }

    private func makeExportProvenanceJSON() -> String {
        let payload = ExportProvenanceMetadata(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            gitRevision: makeExportGitRevision(),
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            mode: activeMode.rawValue,
            settings: makeExportSettingsSnapshot(),
            generatedPalette: makeGeneratedPaletteSnapshot(),
            sourceMetadata: MetadataJSONValue(sourceImageMetadata.properties)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
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
            kuwaharaStrength: kuwaharaStrength,
            postSimplificationStrength: postSimplificationStrength,
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

    private func exportPixelSize(for image: UIImage) -> CGSize {
        if let cgImage = image.cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        return CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
    }

    private func imageContainsAlpha(_ image: UIImage) -> Bool {
        switch image.cgImage?.alphaInfo {
        case .none?, .noneSkipFirst?, .noneSkipLast?, nil:
            return false
        default:
            return true
        }
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
        kuwaharaTask?.cancel()
        abstractionGeneration += 1
        let generation = abstractionGeneration

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
        let kuwaharaRadius = self.kuwaharaRadius

        isProcessing = true
        isSimplifying = true
        processingProgress = 0
        processingLabel = "Abstracting…"
        processingIsIndeterminate = false
        errorMessage = nil

        abstractionTask = Task {
            do {
                let abstracted = try await abstractionOperation(
                    source,
                    downscale,
                    method,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.processingProgress = p }
                    }
                )
                try Task.checkCancellation()

                // Apply Kuwahara post-filter if enabled
                var filteredImage: UIImage? = nil
                if kuwaharaRadius > 0 {
                    await MainActor.run {
                        guard self.abstractionGeneration == generation else { return }
                        self.processingLabel = "Filtering…"
                        self.processingIsIndeterminate = true
                    }
                    filteredImage = await kuwaharaOperation(abstracted, kuwaharaRadius)
                }
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.abstractionGeneration == generation else { return }
                    self.abstractedImage = abstracted
                    self.kuwaharaFilteredImage = filteredImage
                    self.isSimplifying   = false
                    self.isProcessing    = false
                    self.processingLabel = "Processing…"
                    if self.depthConfig.enabled {
                        self.computeDepthMap()
                    }
                    self.triggerProcessing()
                }
            } catch is CancellationError {
                // superseded by a newer request
            } catch {
                await MainActor.run {
                    guard self.abstractionGeneration == generation else { return }
                    self.isSimplifying = false
                    self.isProcessing = false
                    self.processingLabel = "Processing…"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func resetAbstraction() {
        abstractionTask?.cancel()
        kuwaharaTask?.cancel()
        abstractionGeneration += 1
        isSimplifying = false
        abstractedImage = nil
        kuwaharaFilteredImage = nil
        isolatedProcessedImage = nil
        processedPixelBands = []
        processingLabel = "Processing…"
        processingIsIndeterminate = false
        if kuwaharaStrength > 0 {
            applyKuwahara()
        } else {
            triggerProcessing()
        }
    }

    /// Apply the Kuwahara post-filter to the current base image
    /// (abstractedImage if available, otherwise sourceImage).
    /// Call this when only `kuwaharaStrength` changes without re-running the SR model.
    func applyKuwahara() {
        kuwaharaTask?.cancel()

        guard kuwaharaStrength > 0 else {
            kuwaharaFilteredImage = nil
            triggerProcessing()
            return
        }

        guard let source = abstractedImage ?? sourceImage else {
            kuwaharaFilteredImage = nil
            return
        }

        let radius = kuwaharaRadius

        isProcessing = true
        processingProgress = 0
        processingLabel = "Filtering…"
        processingIsIndeterminate = true

        kuwaharaTask = Task {
            let filtered = await kuwaharaOperation(source, radius)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.kuwaharaFilteredImage = filtered
                self.isProcessing = false
                self.processingIsIndeterminate = false
                self.processingLabel = "Processing…"
                if self.depthConfig.enabled {
                    self.computeDepthMap()
                }
                self.triggerProcessing()
            }
        }
    }

    /// Run a Kuwahara filter pass on the mode-processed image to smooth
    /// quantisation artefacts. Called automatically after `triggerProcessing()`
    /// finishes when `postSimplificationIsEnabled` is true, or when the user
    /// adjusts the post-simplification strength slider.
    func applyPostSimplification() {
        postSimplificationTask?.cancel()

        guard postSimplificationIsEnabled,
              activeMode != .original,
              let source = processedImage
        else {
            postSimplifiedImage = nil
            return
        }

        postSimplificationGeneration += 1
        let generation = postSimplificationGeneration

        let radius = postSimplificationRadius

        isProcessing = true
        processingProgress = 0
        processingLabel = "Smoothing…"
        processingIsIndeterminate = true

        postSimplificationTask = Task {
            let smoothed = await kuwaharaOperation(source, radius)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.postSimplificationGeneration == generation else { return }
                self.postSimplifiedImage = smoothed
                self.isProcessing = false
                self.processingIsIndeterminate = false
                self.processingLabel = "Processing…"
            }
        }
    }

    func toggleIsolatedBand(_ band: Int) {
        isolatedBand = isolatedBand == band ? nil : band
        refreshIsolatedProcessedImage()
    }

    func toggleIsolatedBand(atNormalizedPoint point: CGPoint) {
        guard activeMode == .value || activeMode == .color,
              let processedImage,
              let cgImage = processedImage.cgImage,
              !processedPixelBands.isEmpty
        else { return }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return }

        let x = min(max(Int((point.x * CGFloat(width)).rounded(.down)), 0), width - 1)
        let y = min(max(Int((point.y * CGFloat(height)).rounded(.down)), 0), height - 1)
        let pixelIndex = y * width + x
        guard processedPixelBands.indices.contains(pixelIndex) else { return }

        toggleIsolatedBand(processedPixelBands[pixelIndex])
    }

    func clearIsolatedBandSelection() {
        guard isolatedBand != nil else { return }
        isolatedBand = nil
        refreshIsolatedProcessedImage()
    }

    private func refreshIsolatedProcessedImage() {
        guard activeMode == .value || activeMode == .color,
              let isolatedBand,
              let processedImage else {
            isolatedProcessedImage = nil
            return
        }

        isolatedProcessedImage = BandIsolationRenderer.isolate(
            image: processedImage,
            pixelBands: processedPixelBands,
            selectedBand: isolatedBand
        )
    }

    // MARK: - Depth processing

    func computeDepthMap() {
        depthTask?.cancel()

        guard let source = displayBaseImage else {
            depthProcessedImage = nil
            return
        }

        guard depthConfig.enabled else {
            depthProcessedImage = nil
            return
        }

        depthGeneration += 1
        let generation = depthGeneration

        isProcessing = true
        processingLabel = "Estimating depth…"
        processingIsIndeterminate = true

        depthTask = Task {
            do {
                let result = try await depthMapOperation(source)
                try Task.checkCancellation()

                let range = DepthEstimator.depthRange(from: result)

                await MainActor.run {
                    guard self.depthGeneration == generation else { return }
                    let isFirstCompute = self.depthMap == nil
                    self.depthMap = result
                    self.depthRange = range
                    // Only set default cutoff on the first depth compute;
                    // subsequent re-computes (e.g. after simplification changes)
                    // preserve the user’s chosen value.
                    if isFirstCompute {
                        let span = range.upperBound - range.lowerBound
                        self.depthConfig.foregroundCutoff = range.lowerBound + span / 3.0
                        self.depthConfig.backgroundCutoff = range.lowerBound + span * 2.0 / 3.0
                    }
                    self.processingIsIndeterminate = false
                    self.processingLabel = "Processing…"
                    self.isProcessing = false
                    self.applyDepthEffects()
                    self.recomputeContours()
                }
            } catch is CancellationError {
                // superseded
            } catch {
                await MainActor.run {
                    guard self.depthGeneration == generation else { return }
                    self.isProcessing = false
                    self.processingIsIndeterminate = false
                    self.processingLabel = "Processing…"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func applyDepthEffects() {
        depthEffectTask?.cancel()

        guard depthConfig.enabled, let depth = depthMap else {
            depthProcessedImage = nil
            return
        }

        // Determine source: mode-processed output, or displayBaseImage in original mode
        let source: UIImage?
        if activeMode == .original {
            source = displayBaseImage
        } else {
            source = isolatedProcessedImage ?? processedImage ?? displayBaseImage
        }
        guard let sourceImage = source else {
            depthProcessedImage = nil
            return
        }

        let config = depthConfig

        depthEffectGeneration += 1
        let gen = depthEffectGeneration

        isProcessing = true
        processingLabel = "Applying depth…"
        processingIsIndeterminate = true

        depthEffectTask = Task {
            let result = depthEffectOperation(sourceImage, depth, config)
            await MainActor.run {
                guard self.depthEffectGeneration == gen else { return }
                self.isProcessing = false
                guard !Task.isCancelled else { return }
                self.depthProcessedImage = result
                self.processingIsIndeterminate = false
                self.processingLabel = "Processing…"
            }
        }
    }

    func resetDepthProcessing() {
        depthTask?.cancel()
        depthEffectTask?.cancel()
        depthPreviewDismissTask?.cancel()
        contourTask?.cancel()
        depthGeneration += 1
        depthEffectGeneration += 1
        contourGeneration += 1
        depthMap = nil
        depthProcessedImage = nil
        isEditingDepthThreshold = false
        depthSliderActive = false
        depthThresholdPreview = nil
        cachedDepthTexture = nil
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
        guard let depth = depthMap else {
            isEditingDepthThreshold = false
            depthThresholdPreview = nil
            cachedDepthTexture = nil
            return
        }
        // Create the Metal texture once and cache it for the drag session
        if cachedDepthTexture == nil {
            cachedDepthTexture = MetalContext.shared?.makeDepthTexture(from: depth)
        }
        let bg = depthConfig.backgroundCutoff
        isEditingDepthThreshold = true
        depthThresholdPreview = DepthProcessor.thresholdPreview(
            depthMap: depth,
            backgroundCutoff: bg,
            cachedDepthTexture: cachedDepthTexture
        )
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

    // MARK: - Contour line generation

    func recomputeContours() {
        contourTask?.cancel()
        guard contourConfig.enabled, let depth = depthMap else {
            contourSegments = []
            return
        }
        contourGeneration += 1
        let gen = contourGeneration
        let cfg = contourConfig
        let depthCfg = depthConfig
        let range = depthRange
        contourTask = Task {
            let segs = await Task.detached(priority: .userInitiated) {
                ContourGenerator.generateSegments(
                    depthMap: depth,
                    levels: cfg.levels,
                    depthRange: range,
                    backgroundCutoff: depthCfg.backgroundCutoff
                )
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.contourGeneration == gen else { return }
                self.contourSegments = segs
            }
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

private struct ExportProvenanceMetadata: Encodable {
    var appVersion: String
    var buildNumber: String
    var gitRevision: String
    var exportedAt: String
    var mode: String
    var settings: ExportSettingsMetadata
    var generatedPalette: [ExportGeneratedPaletteMetadata]
    var sourceMetadata: MetadataJSONValue
}

private struct ExportSettingsMetadata: Encodable {
    var abstractionStrength: Double
    var abstractionMethod: String
    var kuwaharaStrength: Double
    var postSimplificationStrength: Double
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

private enum MetadataJSONValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([MetadataJSONValue])
    case object([String: MetadataJSONValue])
    case null

    init(_ value: Any?) {
        guard let value else {
            self = .null
            return
        }

        switch value {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let dictionary as [String: Any]:
            self = .object(
                dictionary.reduce(into: [String: MetadataJSONValue]()) { result, entry in
                    result[entry.key] = MetadataJSONValue(entry.value)
                }
            )
        case let dictionary as NSDictionary:
            var object: [String: MetadataJSONValue] = [:]
            for (key, value) in dictionary {
                object[String(describing: key)] = MetadataJSONValue(value)
            }
            self = .object(object)
        case let array as [Any]:
            self = .array(array.map(MetadataJSONValue.init))
        case let array as NSArray:
            self = .array(array.map(MetadataJSONValue.init))
        case let date as Date:
            self = .string(ISO8601DateFormatter().string(from: date))
        case let data as Data:
            self = .string(data.base64EncodedString())
        default:
            self = .string(String(describing: value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
