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

    typealias SimplifyOperation = @Sendable (
        UIImage,
        CGFloat,
        SimplificationMethod,
        @escaping @Sendable (Double) -> Void
    ) async throws -> UIImage

    // Source images
    @Published var fullResolutionOriginalImage: UIImage? = nil
    @Published var originalImage: UIImage?  = nil
    @Published var sourceImage: UIImage?    = nil

    // Processed results
    @Published var processedImage: UIImage? = nil
    @Published var paletteColors: [Color]   = []
    @Published var paletteBands: [Int]      = []

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
    @Published var simplifyEnabled: Bool    = true
    /// Simplification strength 0–1. Maps to downscale factor 2–12.
    @Published var simplifyStrength: Double  = 0.5
    @Published var simplificationMethod: SimplificationMethod = .apisr

    // Simplified image (after upscale/denoise)
    @Published var simplifiedImage: UIImage? = nil

    private var processingTask: Task<Void, Never>? = nil
    private let processOperation: ProcessOperation
    /// Incremented on every triggerProcessing() call; lets each task know if it is still current.
    private var processingGeneration: Int = 0

    private let simplifyOperation: SimplifyOperation
    private var simplifyTask: Task<Void, Never>? = nil
    private var simplifyGeneration: Int = 0

    private var loadingTask: Task<Void, Never>? = nil
    private var processedPixelBands: [Int] = []

    var availableSimplificationMethods: [SimplificationMethod] {
        SimplificationMethod.allCases.filter { method in
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
        simplifyOperation: SimplifyOperation? = nil
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
        self.simplifyOperation = simplifyOperation ?? { image, downscale, method, onProgress in
            try await ImageSimplifier.simplify(
                image: image,
                downscale: downscale,
                method: method,
                onProgress: onProgress
            )
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            ImageSimplifier.clearModelCache()
        }
    }

    var displayBaseImage: UIImage? { simplifiedImage ?? sourceImage }

    var currentDisplayImage: UIImage? {
        activeMode == .original ? displayBaseImage : (isolatedProcessedImage ?? processedImage ?? displayBaseImage)
    }

    func loadImage(_ image: UIImage) {
        // Cancel any in-flight work before starting fresh.
        loadingTask?.cancel()
        processingTask?.cancel()
        simplifyTask?.cancel()

        // Show the picked image immediately, then swap in the scaled version
        // once preprocessing finishes so the canvas never blanks out.
        fullResolutionOriginalImage   = image
        originalImage             = image
        sourceImage               = image
        simplifiedImage           = nil
        processedImage            = nil
        isolatedProcessedImage    = nil
        processedPixelBands       = []
        paletteColors             = []
        paletteBands              = []
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
            if simplifyEnabled {
                applySimplify()
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

        processingTask = Task {
            do {
                let result = try await processOperation(
                    source,
                    activeMode,
                    valueConfig,
                    colorConfig,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.processingProgress = p }
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.processedImage  = result.image
                    self.processedPixelBands = result.pixelBands
                    self.paletteColors   = result.palette
                    self.paletteBands    = result.paletteBands
                    self.processingProgress = 1
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
        triggerProcessing()
    }

    func exportCurrentImage() -> UIImage? {
        if activeMode == .original, let fullResolutionOriginalImage {
            return fullResolutionOriginalImage
        }
        return currentDisplayImage
    }

    func applySimplify() {
        guard let source = sourceImage else { return }

        simplifyTask?.cancel()
        simplifyGeneration += 1
        let generation = simplifyGeneration

        // Normalize the downscale factor to the image resolution so that the
        // absolute intermediate pixel size — what determines the visual degree of
        // simplification — stays consistent regardless of the input dimensions.
        // At the reference resolution (1600 px) the mapping is the full 2–12×
        // range; for smaller images the factor scales down proportionally so that
        // lower-resolution photos are not over-simplified at the same slider value.
        let referenceResolution: CGFloat = 1600.0
        let maxDimension = max(source.size.width, source.size.height)
        let resolutionScale = maxDimension / referenceResolution
        let rawDownscale = 2.0 + simplifyStrength * 10.0
        let downscale = max(1.0, CGFloat(rawDownscale) * resolutionScale)
        let method = simplificationMethod

        isProcessing = true
        processingProgress = 0
        processingLabel = "Simplifying…"
        processingIsIndeterminate = false
        errorMessage = nil

        simplifyTask = Task {
            do {
                let simplified = try await simplifyOperation(
                    source,
                    downscale,
                    method,
                    { [weak self] p in
                        Task { @MainActor [weak self] in self?.processingProgress = p }
                    }
                )
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.simplifyGeneration == generation else { return }
                    self.simplifiedImage = simplified
                    self.isProcessing    = false
                    self.processingLabel = "Processing…"
                    self.triggerProcessing()
                }
            } catch is CancellationError {
                // superseded by a newer request
            } catch {
                await MainActor.run {
                    guard self.simplifyGeneration == generation else { return }
                    self.isProcessing = false
                    self.processingLabel = "Processing…"
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func resetSimplify() {
        simplifyTask?.cancel()
        simplifyGeneration += 1
        simplifiedImage = nil
        isolatedProcessedImage = nil
        processedPixelBands = []
        processingLabel = "Processing…"
        processingIsIndeterminate = false
        triggerProcessing()
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
