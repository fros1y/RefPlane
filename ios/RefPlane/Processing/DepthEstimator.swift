import UIKit
import CoreML
import CoreImage
import ImageIO
import AVFoundation
import os

// MARK: - Depth map generation via Depth Anything V2 (CoreML)

/// Generates a monocular depth map using the Depth Anything V2 CoreML model.
/// Convention: 0 = nearest (foreground), 1 = farthest (background).
enum DepthEstimator {

    private static let logger = Logger(subsystem: "com.refplane.app", category: "DepthEstimator")

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

    static func depthRange(from image: UIImage) -> ClosedRange<Double> {
        guard let cgImage = image.cgImage else {
            return 0...1
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return 0...1
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
            return 0...1
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minValue = 1.0
        var maxValue = 0.0
        for pixel in pixels {
            let value = Double(pixel) / 255.0
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }

        let epsilon = 1.0 / 255.0
        if maxValue - minValue < epsilon {
            // Keep a minimally non-zero range centered on observed data so
            // UI sliders do not expand to 0...1 and create dead interaction zones.
            let center = (minValue + maxValue) * 0.5
            let lower = max(0.0, center - epsilon * 0.5)
            let upper = min(1.0, center + epsilon * 0.5)
            if upper > lower {
                return lower...upper
            }
            // Edge case near 0 or 1 where clamping collapsed the interval.
            let fallbackLower = max(0.0, minValue - epsilon)
            let fallbackUpper = min(1.0, maxValue + epsilon)
            return fallbackLower...max(fallbackUpper, fallbackLower + epsilon)
        }

        return minValue...maxValue
    }

    // MARK: - Embedded depth extraction

    /// Extract an embedded depth or disparity map from raw image data.
    /// Returns nil when the image carries no auxiliary depth payload.
    static func extractEmbeddedDepth(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            logger.error("Embedded depth extraction failed: could not create image source")
            return nil
        }

        let exifOrientation = imageExifOrientation(from: source)

        let auxiliaryTypes: [(type: CFString, shouldInvert: Bool, pixelFormat: OSType)] = [
            (kCGImageAuxiliaryDataTypeDisparity, true, kCVPixelFormatType_DisparityFloat32),
            (kCGImageAuxiliaryDataTypeDepth, false, kCVPixelFormatType_DepthFloat32)
        ]

        var foundAuxiliaryPayload = false

        for auxiliaryType in auxiliaryTypes {
            guard
                let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType.type) as? [AnyHashable: Any],
                let depthData = try? AVDepthData(fromDictionaryRepresentation: info)
            else {
                continue
            }

            foundAuxiliaryPayload = true

            let oriented = depthData.applyingExifOrientation(exifOrientation)
            let converted = oriented.converting(toDepthDataType: auxiliaryType.pixelFormat)
            let pixelBuffer = converted.depthDataMap
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let auxiliaryName = auxiliaryType.type as String
            if let stats = floatRange(from: pixelBuffer) {
                logger.info(
                    "Embedded depth payload type=\(auxiliaryName, privacy: .public) size=\(width)x\(height) invert=\(auxiliaryType.shouldInvert) rawMin=\(stats.min, format: .fixed(precision: 6)) rawMax=\(stats.max, format: .fixed(precision: 6)) rawMean=\(stats.mean, format: .fixed(precision: 6))"
                )
            } else {
                logger.info(
                    "Embedded depth payload type=\(auxiliaryName, privacy: .public) size=\(width)x\(height) invert=\(auxiliaryType.shouldInvert) (raw range unavailable)"
                )
            }

            guard
                let result = normalizedDepthImage(
                    from: pixelBuffer,
                    invert: auxiliaryType.shouldInvert
                )
            else {
                logger.error("Embedded depth payload type=\(auxiliaryName, privacy: .public) failed during float normalization")
                continue
            }

            let normalizedRange = depthRange(from: result)
            logger.info(
                "Embedded depth normalized range min=\(normalizedRange.lowerBound, format: .fixed(precision: 6)) max=\(normalizedRange.upperBound, format: .fixed(precision: 6))"
            )
            return result
        }

        if !foundAuxiliaryPayload {
            logger.info("No embedded disparity/depth payload found in selected image data")
        }

        return nil
    }

    static func resize(_ depthMap: UIImage, toMatch source: UIImage) -> UIImage {
        guard let cgImage = depthMap.cgImage else {
            return depthMap
        }

        let width = source.cgImage?.width ?? max(Int((source.size.width * source.scale).rounded()), 1)
        let height = source.cgImage?.height ?? max(Int((source.size.height * source.scale).rounded()), 1)
        return UIImage(cgImage: resizeGrayscale(cgImage, toWidth: width, height: height))
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
    private static func cgImageFromGrayscaleBuffer(_ buffer: CVPixelBuffer, invert: Bool = true) throws -> CGImage {
        var ciImage = CIImage(cvPixelBuffer: buffer)
        if invert, let invertFilter = CIFilter(name: "CIColorInvert") {
            invertFilter.setValue(ciImage, forKey: kCIInputImageKey)
            if let inverted = invertFilter.outputImage {
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

    private static func normalizedDepthImage(from pixelBuffer: CVPixelBuffer, invert: Bool) -> UIImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let floatStride = bytesPerRow / MemoryLayout<Float32>.stride
        let rowPointer = baseAddress.assumingMemoryBound(to: Float32.self)

        var validValues: [Float] = []
        validValues.reserveCapacity(width * height / 2)

        for y in 0..<height {
            let rowStart = rowPointer.advanced(by: y * floatStride)
            for x in 0..<width {
                let value = rowStart[x]
                if value.isFinite && value > 0 {
                    validValues.append(value)
                }
            }
        }

        guard validValues.count > 32 else {
            logger.warning("Embedded depth normalization aborted: only \(validValues.count) valid float samples")
            return nil
        }

        validValues.sort()

        let lowPercentile = percentile(in: validValues, p: 0.005)
        let highPercentile = percentile(in: validValues, p: 0.998)
        let gamma: Float = 0.92

        let minValue = validValues.first ?? lowPercentile
        let maxValue = validValues.last ?? highPercentile
        let lowerBound = lowPercentile
        let upperBound = max(highPercentile, lowPercentile + 1e-8)

        logger.info(
            "Embedded depth normalization window rawMin=\(Double(minValue), format: .fixed(precision: 6)) rawMax=\(Double(maxValue), format: .fixed(precision: 6)) p0_5=\(Double(lowPercentile), format: .fixed(precision: 6)) p99_8=\(Double(highPercentile), format: .fixed(precision: 6)) gamma=\(Double(gamma), format: .fixed(precision: 3))"
        )

        var grayscale = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let rowStart = rowPointer.advanced(by: y * floatStride)
            let rowOffset = y * width
            for x in 0..<width {
                let value = rowStart[x]
                guard value.isFinite && value > 0 else {
                    grayscale[rowOffset + x] = 0
                    continue
                }

                let normalized = (value - lowerBound) / (upperBound - lowerBound)
                let clamped = max(0.0, min(1.0, normalized))
                let curved = pow(clamped, gamma)
                let mapped = invert ? (1.0 - curved) : curved
                grayscale[rowOffset + x] = UInt8((mapped * 255.0).rounded())
            }
        }

        guard let context = CGContext(
            data: &grayscale,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: image)
    }

    private static func percentile(in sorted: [Float], p: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let clampedP = max(0, min(1, p))
        let index = Int((Float(sorted.count - 1) * clampedP).rounded(.toNearestOrAwayFromZero))
        return sorted[index]
    }

    private static func imageExifOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
            let orientation = CGImagePropertyOrientation(rawValue: rawValue)
        else {
            return .up
        }
        return orientation
    }

    private static func floatRange(from pixelBuffer: CVPixelBuffer) -> (min: Double, max: Double, mean: Double)? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let floatStride = bytesPerRow / MemoryLayout<Float32>.stride
        let rowPointer = baseAddress.assumingMemoryBound(to: Float32.self)

        var minValue = Double.greatestFiniteMagnitude
        var maxValue = -Double.greatestFiniteMagnitude
        var sum = 0.0
        var sampleCount = 0

        for y in 0..<height {
            let rowStart = rowPointer.advanced(by: y * floatStride)
            for x in 0..<width {
                let value = Double(rowStart[x])
                guard value.isFinite else {
                    continue
                }
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
                sum += value
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return nil
        }

        return (minValue, maxValue, sum / Double(sampleCount))
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
