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
            case .metalShader:
                return MetalContext.shared != nil
            }
        }
    }

    init(
        processOperation: ProcessOperation? = nil,
        abstractionOperation: AbstractionOperation? = nil,
        kuwaharaOperation: KuwaharaOperation? = nil
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
            await Task.detached(priority: .userInitiated) {
                guard let ctx = MetalContext.shared, let cg = image.cgImage else { return nil }
                return ctx.anisotropicKuwahara(cg, radius: radius)
            }.value
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ImageAbstractor.clearModelCache()
        }
    }

    var displayBaseImage: UIImage? { kuwaharaFilteredImage ?? abstractedImage ?? sourceImage }

    var currentDisplayImage: UIImage? {
        activeMode == .original ? displayBaseImage : (isolatedProcessedImage ?? processedImage ?? displayBaseImage)
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

        // Show the picked image immediately, then swap in the scaled version
        // once preprocessing finishes so the canvas never blanks out.
        fullResolutionOriginalImage   = image
        originalImage             = image
        sourceImage               = image
        abstractedImage           = nil
        kuwaharaFilteredImage     = nil
        processedImage            = nil
        isolatedProcessedImage    = nil
        processedPixelBands       = []
        paletteColors             = []
        paletteBands              = []
        pigmentRecipes            = nil
        selectedTubes             = []
        clippedRecipeIndices      = []
        isolatedBand              = nil
        errorMessage              = nil
        isProcessing              = true
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
        guard gridConfig.enabled else { return image }
        return renderGridOnto(image)
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
        let kuwaharaRadius = Int((kuwaharaStrength * 8).rounded())

        isProcessing = true
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
                    filteredImage = await kuwaharaOperation(abstracted, kuwaharaRadius)
                }
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.abstractionGeneration == generation else { return }
                    self.abstractedImage = abstracted
                    self.kuwaharaFilteredImage = filteredImage
                    self.isProcessing    = false
                    self.processingLabel = "Processing…"
                    self.triggerProcessing()
                }
            } catch is CancellationError {
                // superseded by a newer request
            } catch {
                await MainActor.run {
                    guard self.abstractionGeneration == generation else { return }
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

        let radius = Int((kuwaharaStrength * 8).rounded())

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
}
