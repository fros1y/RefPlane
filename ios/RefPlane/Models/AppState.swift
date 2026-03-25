import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    // Source images
    @Published var originalImage: UIImage?  = nil
    @Published var sourceImage: UIImage?    = nil   // after crop

    // Processed results
    @Published var processedImage: UIImage? = nil
    @Published var paletteColors: [Color]   = []
    @Published var paletteBands: [Int]      = []

    // UI state
    @Published var activeMode: RefPlaneMode = .original
    @Published var isProcessing: Bool       = false
    @Published var processingProgress: Double = 0
    @Published var showCompare: Bool        = false
    @Published var showCrop: Bool           = false
    @Published var isolatedBand: Int?       = nil
    @Published var errorMessage: String?    = nil

    // Configs
    @Published var gridConfig: GridConfig   = GridConfig()
    @Published var valueConfig: ValueConfig = ValueConfig()
    @Published var colorConfig: ColorConfig = ColorConfig()
    @Published var simplifyEnabled: Bool    = false
    /// Simplification strength 0–1. Maps to downscale factor 2–8.
    @Published var simplifyStrength: Double  = 0.5

    // Simplified image (after upscale/denoise)
    @Published var simplifiedImage: UIImage? = nil

    private var processingTask: Task<Void, Never>? = nil
    private let processor = ImageProcessor()
    /// Incremented on every triggerProcessing() call; lets each task know if it is still current.
    private var processingGeneration: Int = 0

    var displayBaseImage: UIImage? { simplifiedImage ?? sourceImage }

    var currentDisplayImage: UIImage? {
        activeMode == .original ? displayBaseImage : (processedImage ?? displayBaseImage)
    }

    func loadImage(_ image: UIImage) {
        let maxSize: CGFloat = 1600
        let scaled = image.scaledDown(toMaxDimension: maxSize)
        originalImage  = scaled
        sourceImage    = scaled
        simplifiedImage = nil
        processedImage = nil
        paletteColors  = []
        paletteBands   = []
        isolatedBand   = nil
        triggerProcessing()
    }

    func applyCrop(_ crop: CGRect) {
        guard let original = originalImage else { return }
        let cropped = original.cropped(to: crop)
        sourceImage    = cropped
        simplifiedImage = nil
        processedImage = nil
        paletteColors  = []
        paletteBands   = []
        isolatedBand   = nil
        showCrop       = false
        triggerProcessing()
    }

    func triggerProcessing() {
        processingTask?.cancel()
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

        processingGeneration += 1
        let myGeneration = processingGeneration

        processingTask = Task {
            await MainActor.run { self.isProcessing = true; self.processingProgress = 0 }
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
        activeMode = mode
        isolatedBand = nil
        triggerProcessing()
    }

    func exportCurrentImage() -> UIImage? {
        currentDisplayImage
    }

    func applySimplify() {
        guard let source = sourceImage else { return }
        // Map strength 0–1 → downscale 2–8 (same as web: lerp(2, 8, s))
        let downscale = CGFloat(2.0 + simplifyStrength * 6.0)
        Task {
            await MainActor.run { self.isProcessing = true }
            let simplified = await ImageSimplifier.simplify(image: source, downscale: downscale)
            await MainActor.run {
                self.simplifiedImage = simplified
                self.isProcessing    = false
                self.triggerProcessing()
            }
        }
    }

    func resetSimplify() {
        simplifiedImage = nil
        triggerProcessing()
    }
}
