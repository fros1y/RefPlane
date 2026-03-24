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

    // Simplified image (after upscale/denoise)
    @Published var simplifiedImage: UIImage? = nil

    private var processingTask: Task<Void, Never>? = nil
    private let processor = ImageProcessor()

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
        guard let source = sourceImage else { return }
        guard activeMode != .original else {
            processedImage = nil
            return
        }

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
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.processedImage  = result.image
                    self.paletteColors   = result.palette
                    self.paletteBands    = result.paletteBands
                    self.isProcessing    = false
                    self.processingProgress = 1
                }
            } catch is CancellationError {
                // Silently ignore
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
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
        Task {
            await MainActor.run { self.isProcessing = true }
            let simplified = await ImageSimplifier.simplify(image: source)
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
