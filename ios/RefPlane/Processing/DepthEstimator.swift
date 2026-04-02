import UIKit
import CoreML
import CoreImage

// MARK: - Depth map generation via Depth Anything V2 (CoreML)

/// Generates a monocular depth map using the Depth Anything V2 CoreML model.
/// Convention: 0 = nearest (foreground), 1 = farthest (background).
enum DepthEstimator {

    /// The model's expected input dimensions.
    private static let modelWidth = 518
    private static let modelHeight = 392

    // MARK: - Model cache

    private static let modelStore = DepthModelStore()

    /// Evict the cached model. Call on memory warning.
    static func clearModelCache() {
        Task { await modelStore.clear() }
    }

    // MARK: - Public API

    /// Generate a normalized depth map from the given image.
    ///
    /// Returns a single-channel grayscale `UIImage` at the same pixel dimensions
    /// as the source. Convention: 0 = nearest (foreground), 1 = farthest (background).
    static func estimateDepth(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw DepthEstimatorError.invalidInput
        }

        let targetWidth = cgImage.width
        let targetHeight = cgImage.height

        // Load the CoreML model
        let model = try await loadModel()

        // Prepare input: resize source to model dimensions as CVPixelBuffer
        let inputBuffer = try createPixelBuffer(from: cgImage, width: modelWidth, height: modelHeight)
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: inputBuffer)
        ])

        // Run inference
        let output = try await model.prediction(from: featureProvider)

        guard let depthFeature = output.featureValue(for: "depth"),
              let depthBuffer = depthFeature.imageBufferValue else {
            throw DepthEstimatorError.noResult
        }

        // Convert depth output to a CGImage, then resize to source dimensions
        let depthCG = try cgImageFromGrayscaleBuffer(depthBuffer)
        let resized = resizeGrayscale(depthCG, toWidth: targetWidth, height: targetHeight)

        return UIImage(cgImage: resized)
    }

    // MARK: - Model loading

    private static func loadModel() async throws -> MLModel {
        if let cached = await modelStore.model { return cached }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        let name = "DepthAnythingV2SmallF16"

        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: url, configuration: config) {
            await modelStore.insert(model)
            return model
        }

        if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try await MLModel.compileModel(at: url)
            let model = try MLModel(contentsOf: compiledURL, configuration: config)
            await modelStore.insert(model)
            return model
        }

        throw DepthEstimatorError.modelUnavailable
    }

    // MARK: - Pixel buffer helpers

    /// Create an RGB CVPixelBuffer sized to the model's input dimensions.
    private static func createPixelBuffer(from cgImage: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw DepthEstimatorError.bufferAccessFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw DepthEstimatorError.bufferAccessFailed
        }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    /// Extract a CGImage from a grayscale (or single-channel float16) CVPixelBuffer.
    /// The model outputs disparity (bright = near), so we invert to match the
    /// pipeline convention (0 = near, 1 = far).
    private static func cgImageFromGrayscaleBuffer(_ buffer: CVPixelBuffer) throws -> CGImage {
        var ciImage = CIImage(cvPixelBuffer: buffer)
        if let invert = CIFilter(name: "CIColorInvert") {
            invert.setValue(ciImage, forKey: kCIInputImageKey)
            if let inverted = invert.outputImage {
                ciImage = inverted
            }
        }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw DepthEstimatorError.imageCreationFailed
        }
        return cgImage
    }

    /// Resize a CGImage to target dimensions, producing a grayscale CGImage.
    private static func resizeGrayscale(_ cgImage: CGImage, toWidth width: Int, height: Int) -> CGImage {
        let graySpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: graySpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return cgImage
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? cgImage
    }
}

// MARK: - Model cache actor

private actor DepthModelStore {
    private var cachedModel: MLModel?

    var model: MLModel? { cachedModel }
    func insert(_ model: MLModel) { cachedModel = model }
    func clear() { cachedModel = nil }
}

// MARK: - Errors

enum DepthEstimatorError: LocalizedError {
    case invalidInput
    case noResult
    case bufferAccessFailed
    case uniformDepth
    case imageCreationFailed
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidInput:        return "Cannot create CGImage from input"
        case .noResult:            return "Depth estimation produced no result"
        case .bufferAccessFailed:  return "Cannot access depth buffer"
        case .uniformDepth:        return "Scene has uniform depth — no separation found"
        case .imageCreationFailed: return "Failed to create depth image"
        case .modelUnavailable:    return "Depth model not found in app bundle"
        }
    }
}
