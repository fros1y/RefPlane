import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
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
    @Published var fullResolutionOriginalImage: UIImage? = nil
    @Published var originalImage: UIImage?  = nil
    @Published var sourceImage: UIImage?    = nil

    // Processed results
    @Published var processedImage: UIImage? = nil
    @Published var paletteColors: [Color]   = []
    @Published var paletteBands: [Int]      = []
    @Published var pigmentRecipes: [PigmentRecipe]? = nil
    @Published var selectedTubes: [PigmentData] = []
    @Published var clippedRecipeIndices: [Int] = []

    // UI state
    @Published var activeMode: RefPlaneMode = .original
    @Published var isProcessing: Bool       = false
    /// `true` while the image is being loaded or simplified (abstracted);
    /// `false` during actual mode processing. Used to suppress the blur
    /// overlay so the original image stays crisp during simplification.
    @Published var isSimplifying: Bool      = false
    @Published var processingProgress: Double = 0
    @Published var processingLabel: String  = "Processing…"
    @Published var processingIsIndeterminate: Bool = false
    @Published var compareMode: Bool        = false
    @Published var isolatedBand: Int?       = nil
    @Published var errorMessage: String?    = nil
    @Published var panelCollapsed: Bool     = false
    @Published private(set) var isolatedProcessedImage: UIImage? = nil

    // Configs
    @Published var gridConfig: GridConfig   = GridConfig()
    @Published var valueConfig: ValueConfig = ValueConfig()
    @Published var colorConfig: ColorConfig = ColorConfig()
    @Published var depthConfig: DepthConfig = DepthConfig()
    @Published var contourConfig: ContourConfig = ContourConfig()
    @Published var contourSegments: [GridLineSegment] = []

    // Depth results
    @Published var depthMap: UIImage? = nil
    @Published var depthProcessedImage: UIImage? = nil
    /// Actual min/max depth values found in the current depth map (0–1 scale).
    @Published var depthRange: ClosedRange<Double> = 0...1
    /// When true, the canvas shows a depth-threshold preview instead of the
    /// processed image. Set while the user drags a depth cutoff slider.
    @Published var isEditingDepthThreshold: Bool = false
    /// Cached depth-threshold preview image, regenerated as cutoffs change.
    @Published var depthThresholdPreview: UIImage? = nil
    /// Cached Metal texture of the depth map, reused across preview updates for speed.
    var cachedDepthTexture: AnyObject? = nil
    /// True while the user's finger is actively on a depth cutoff slider.
    var depthSliderActive: Bool = false
    /// Abstraction strength 0–1. `0` disables abstraction; positive values map
    /// to the existing downscale-based abstraction range.
    @Published var abstractionStrength: Double  = 0.5
    @Published var abstractionMethod: AbstractionMethod = .apisr
    /// Kuwahara post-filter strength 0–1. `0` disables the filter; positive
    /// values map to a neighbourhood radius of 1–8 applied after the SR model.
    @Published var kuwaharaStrength: Double = 0

    // Abstracted image (after upscale/denoise)
    @Published var abstractedImage: UIImage? = nil
    /// Kuwahara-filtered image applied on top of the abstracted (or source) image.
    @Published var kuwaharaFilteredImage: UIImage? = nil

    private var processingTask: Task<Void, Never>? = nil
    private let processOperation: ProcessOperation
    /// Incremented on every triggerProcessing() call; lets each task know if it is still current.
    private var processingGeneration: Int = 0

    private let abstractionOperation: AbstractionOperation
    private var abstractionTask: Task<Void, Never>? = nil
    private var abstractionGeneration: Int = 0

    private let kuwaharaOperation: KuwaharaOperation
    private var kuwaharaTask: Task<Void, Never>? = nil

    private var loadingTask: Task<Void, Never>? = nil
    private var processedPixelBands: [Int] = []

    private let depthMapOperation: DepthMapOperation
    private let depthEffectOperation: DepthEffectOperation
    private var depthTask: Task<Void, Never>? = nil
    private var depthEffectTask: Task<Void, Never>? = nil
    private var depthPreviewDismissTask: Task<Void, Never>? = nil
    private var depthGeneration: Int = 0

    private var contourTask: Task<Void, Never>? = nil
    private var contourGeneration: Int = 0

    var abstractionIsEnabled: Bool {
        abstractionStrength > 0
    }

    /// Kuwahara neighbourhood radius derived from `kuwaharaStrength`.
    /// Returns 0 when the filter is off, and a value clamped to 1…8 otherwise.
    var kuwaharaRadius: Int {
        guard kuwaharaStrength > 0 else { return 0 }
        return min(max(Int((kuwaharaStrength * 8).rounded()), 1), 8)
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

            // The radius (1–8) is defined relative to a ~600 px reference image.
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

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ImageAbstractor.clearModelCache()
            DepthEstimator.clearModelCache()
        }
    }

    var displayBaseImage: UIImage? { kuwaharaFilteredImage ?? abstractedImage ?? sourceImage }

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

    func loadImage(_ image: UIImage) {
        // Cancel any in-flight work before starting fresh.
        loadingTask?.cancel()
        processingTask?.cancel()
        abstractionTask?.cancel()
        kuwaharaTask?.cancel()
        depthTask?.cancel()
        depthEffectTask?.cancel()

        // Show the picked image immediately, then swap in the scaled version
        // once preprocessing finishes so the canvas never blanks out.
        fullResolutionOriginalImage   = image
        originalImage             = image
        sourceImage               = image
        abstractedImage           = nil
        kuwaharaFilteredImage     = nil
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
        processingTask?.cancel()
        processingIsIndeterminate = false
        errorMessage = nil
        guard let source = displayBaseImage else {
            isProcessing = false
            processingProgress = 0
            return
        }
        guard activeMode != .original else {
            processedImage = nil
            isolatedProcessedImage = nil
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
            await MainActor.run {
                if self.processingGeneration == myGeneration {
                    self.isProcessing = false
                }
            }
        }
    }

    func setMode(_ mode: RefPlaneMode) {
        guard mode != activeMode else { return }
        activeMode = mode
        isolatedBand = nil
        processedImage = nil
        isolatedProcessedImage = nil
        processedPixelBands = []
        paletteColors = []
        paletteBands = []
        pigmentRecipes = nil
        selectedTubes = []
        clippedRecipeIndices = []
        triggerProcessing()
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

    func toggleIsolatedBand(_ band: Int) {
        isolatedBand = isolatedBand == band ? nil : band
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

        guard depthConfig.enabled, let source = displayBaseImage else {
            depthMap = nil
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
                    self.depthMap = result
                    self.depthRange = range
                    // Reset cutoffs to span the actual depth range
                    let span = range.upperBound - range.lowerBound
                    self.depthConfig.foregroundCutoff = range.lowerBound + span / 3.0
                    self.depthConfig.backgroundCutoff = range.lowerBound + span * 2.0 / 3.0
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

        processingLabel = "Applying depth…"
        processingIsIndeterminate = true

        depthEffectTask = Task {
            let result = depthEffectOperation(sourceImage, depth, config)
            guard !Task.isCancelled else { return }
            await MainActor.run {
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
        depthMap = nil
        depthProcessedImage = nil
        isEditingDepthThreshold = false
        depthSliderActive = false
        depthThresholdPreview = nil
        cachedDepthTexture = nil
        depthRange = 0...1
        contourSegments = []
    }

    /// Regenerate the depth-threshold preview image showing which pixels
    /// fall into the background zone. Called while the user drags a cutoff slider.
    func updateDepthThresholdPreview() {
        guard let depth = depthMap else {
            depthThresholdPreview = nil
            return
        }
        // Create the Metal texture once and cache it for the drag session
        if cachedDepthTexture == nil {
            cachedDepthTexture = MetalContext.shared?.makeDepthTexture(from: depth)
        }
        let fg = depthConfig.foregroundCutoff
        let bg = depthConfig.backgroundCutoff
        isEditingDepthThreshold = true
        depthThresholdPreview = DepthProcessor.thresholdPreview(
            depthMap: depth,
            foregroundCutoff: fg,
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
        guard isEditingDepthThreshold else { return }
        isEditingDepthThreshold = false
        depthThresholdPreview = nil
        cachedDepthTexture = nil
        applyDepthEffects()
        recomputeContours()
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
