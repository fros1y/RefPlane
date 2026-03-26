import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    // Source images
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
    @Published var showCompare: Bool        = false
    @Published var compareMode: Bool        = false
    @Published var isolatedBand: Int?       = nil
    @Published var errorMessage: String?    = nil

    // Configs
    @Published var gridConfig: GridConfig   = GridConfig()
    @Published var valueConfig: ValueConfig = ValueConfig()
    @Published var colorConfig: ColorConfig = ColorConfig()
    @Published var simplifyEnabled: Bool    = false
    /// Simplification strength 0–1. Maps to downscale factor 2–12.
    @Published var simplifyStrength: Double  = 0.5
    @Published var simplificationMethod: SimplificationMethod = .apisr

    // Simplified image (after upscale/denoise)
    @Published var simplifiedImage: UIImage? = nil

    private var processingTask: Task<Void, Never>? = nil
    private let processor = ImageProcessor()
    /// Incremented on every triggerProcessing() call; lets each task know if it is still current.
    private var processingGeneration: Int = 0

    private var simplifyTask: Task<Void, Never>? = nil
    private var simplifyGeneration: Int = 0

    private var loadingTask: Task<Void, Never>? = nil

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

    init() {
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
        activeMode == .original ? displayBaseImage : (processedImage ?? displayBaseImage)
    }

    func loadImage(_ image: UIImage) {
        // Cancel any in-flight work before starting fresh.
        loadingTask?.cancel()
        processingTask?.cancel()
        simplifyTask?.cancel()

        // Show a loading spinner immediately — before async scaling —
        // so the UI never looks frozen after the photo picker closes.
        originalImage             = nil
        sourceImage               = nil
        simplifiedImage           = nil
        processedImage            = nil
        paletteColors             = []
        paletteBands              = []
        isolatedBand              = nil
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
            processingLabel           = "Processing…"
            processingIsIndeterminate = false
            triggerProcessing()
        }
    }

    func triggerProcessing() {
        processingTask?.cancel()
        processingIsIndeterminate = false
        guard let source = displayBaseImage else {
            isProcessing = false
            processingProgress = 0
            return
        }
        guard activeMode != .original else {
            processedImage = nil
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
                let result = try await processor.process(
                    image: source,
                    mode: activeMode,
                    valueConfig: valueConfig,
                    colorConfig: colorConfig,
                    onProgress: { [weak self] p in
                        Task { @MainActor [weak self] in self?.processingProgress = p }
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.processedImage  = result.image
                    self.paletteColors   = result.palette
                    self.paletteBands    = result.paletteBands
                    self.processingProgress = 1
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
        paletteColors = []
        paletteBands = []
        triggerProcessing()
    }

    func exportCurrentImage() -> UIImage? {
        currentDisplayImage
    }

    func applySimplify() {
        guard let source = sourceImage else { return }

        simplifyTask?.cancel()
        simplifyGeneration += 1
        let generation = simplifyGeneration

        let downscale = CGFloat(2.0 + simplifyStrength * 10.0)
        let method = simplificationMethod

        isProcessing = true
        processingProgress = 0
        processingLabel = "Simplifying…"
        errorMessage = nil

        simplifyTask = Task {
            do {
                let simplified = try await ImageSimplifier.simplify(
                    image: source,
                    downscale: downscale,
                    method: method,
                    onProgress: { [weak self] p in
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
        simplifiedImage = nil
        triggerProcessing()
    }
}
