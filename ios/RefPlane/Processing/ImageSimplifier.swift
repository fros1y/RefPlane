import UIKit
import CoreML
import CoreImage

// MARK: - Image simplification using a 4× RealESRGAN CoreML model
//
// Pipeline mirrors the web version's UltraSharp flow:
//   1. Box-downsample the input by `downscale` factor
//   2. Tile the downsampled image into 256×256 patches
//   3. Run each patch through the 4× super-resolution model
//   4. Stitch tiles and scale back to original dimensions
//
// The downsample→upscale cycle replaces fine texture with AI-hallucinated
// detail, producing a simplified/smoothed version of the original image.
// Tiling ensures the downscale factor actually controls simplification:
//   - Low downscale → large intermediate → many tiles → more detail
//   - High downscale → small intermediate → fewer tiles → more simplified
//
// Add RealESRGAN_x4.mlpackage (or a quantized variant) to the Xcode project.
// Download from: https://huggingface.co/marshiyar/RealESRGAN_x4_CoreML

enum ImageSimplifier {

    private static let modelInputSize = 256
    private static let modelOutputSize = 1024  // 4× input

    // MARK: - Model loading (lazy, cached)

    private static var cachedModel: MLModel?

    private static func loadModel() -> MLModel? {
        if let cached = cachedModel { return cached }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        let candidates = ["RealESRGAN_x4", "RealESRGAN_x4_Q-8", "RealESRGAN_x4_pal-4"]
        for name in candidates {
            // Try 1: Xcode-compiled .mlmodelc in bundle
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                if let model = try? MLModel(contentsOf: url, configuration: config) {
                    cachedModel = model
                    print("[ImageSimplifier] Loaded compiled model: \(name).mlmodelc")
                    return model
                }
            }

            // Try 2: .mlpackage in bundle — compile at runtime
            if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                if let compiledURL = try? MLModel.compileModel(at: url),
                   let model = try? MLModel(contentsOf: compiledURL, configuration: config) {
                    cachedModel = model
                    print("[ImageSimplifier] Compiled and loaded: \(name).mlpackage")
                    return model
                }
            }

            // Try 3: .mlmodel (single-file format) in bundle
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
                if let compiledURL = try? MLModel.compileModel(at: url),
                   let model = try? MLModel(contentsOf: compiledURL, configuration: config) {
                    cachedModel = model
                    print("[ImageSimplifier] Compiled and loaded: \(name).mlmodel")
                    return model
                }
            }
        }

        print("[ImageSimplifier] No RealESRGAN CoreML model found in bundle")
        print("[ImageSimplifier] Bundle path: \(Bundle.main.bundlePath)")
        if let items = try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundlePath) {
            let mlItems = items.filter { $0.contains("ESRGAN") || $0.contains("mlmodel") || $0.contains("mlpackage") }
            print("[ImageSimplifier] ML-related bundle items: \(mlItems)")
        }
        return nil
    }

    // MARK: - Public API

    /// Simplify an image using the 4× RealESRGAN super-resolution model.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - downscale: How aggressively to downsample before upscaling (2–8).
    ///                Higher values produce a more abstract/simplified result.
    /// - Returns: The simplified image at the original dimensions.
    static func simplify(image: UIImage, downscale: CGFloat = 4.0) async -> UIImage {
        return await Task.detached(priority: .userInitiated) {
            guard let sourceCG = image.cgImage else { return image }
            let origW = sourceCG.width
            let origH = sourceCG.height

            guard let model = loadModel() else {
                print("[ImageSimplifier] Model unavailable, returning original")
                return image
            }

            // Step 1: Downsample by the strength factor
            let smallW = max(1, Int(round(Double(origW) / Double(downscale))))
            let smallH = max(1, Int(round(Double(origH) / Double(downscale))))
            let small = resizeToPixels(image, width: smallW, height: smallH)
            guard let smallCG = small.cgImage else { return image }

            // Step 2: Process the downsampled image in 256×256 tiles through the model
            guard let upscaled = processInTiles(smallCG, model: model) else { return image }

            // Step 3: Resize back to original pixel dimensions
            return resizeToPixels(upscaled, width: origW, height: origH)
        }.value
    }

    // MARK: - Tile-based ML inference

    /// Process an image through the fixed-size model in tiles, then stitch results.
    ///
    /// The model expects 256×256 input and produces 1024×1024 output (4× upscale).
    /// For images larger than 256×256 we split into tiles, run each through the
    /// model, and composite the outputs. This means:
    ///   - Low downscale → large image → many tiles → preserved detail
    ///   - High downscale → small image → few tiles → simplified/abstract
    private static func processInTiles(_ input: CGImage, model: MLModel) -> UIImage? {
        let srcW = input.width
        let srcH = input.height
        let scale = modelOutputSize / modelInputSize  // 4
        let tileIn = modelInputSize   // 256
        let tileOut = modelOutputSize  // 1024

        let tilesX = max(1, Int(ceil(Double(srcW) / Double(tileIn))))
        let tilesY = max(1, Int(ceil(Double(srcH) / Double(tileIn))))
        let outW = srcW * scale
        let outH = srcH * scale

        print("[ImageSimplifier] Tiling \(srcW)×\(srcH) → \(tilesX)×\(tilesY) tiles (\(tilesX * tilesY) total)")

        // Process each tile through the model
        var tileResults: [(destRect: CGRect, image: CGImage)] = []
        tileResults.reserveCapacity(tilesX * tilesY)

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let srcX = tx * tileIn
                let srcY = ty * tileIn
                let tileW = min(tileIn, srcW - srcX)
                let tileH = min(tileIn, srcH - srcY)

                // Extract tile from the downsampled image
                guard let tileCG = input.cropping(
                    to: CGRect(x: srcX, y: srcY, width: tileW, height: tileH)
                ) else { continue }

                // Pad to 256×256 if this is a partial edge tile
                let modelInputCG: CGImage
                if tileW == tileIn && tileH == tileIn {
                    modelInputCG = tileCG
                } else {
                    guard let padded = padTileToModelSize(tileCG) else { continue }
                    modelInputCG = padded
                }

                // Run model inference → 1024×1024
                guard let outputImage = runModel(model, input: modelInputCG),
                      let outCG = outputImage.cgImage else { continue }

                // Crop to valid region (only needed for padded edge tiles)
                let validW = tileW * scale
                let validH = tileH * scale
                let drawCG: CGImage
                if validW < tileOut || validH < tileOut {
                    drawCG = outCG.cropping(
                        to: CGRect(x: 0, y: 0, width: validW, height: validH)
                    ) ?? outCG
                } else {
                    drawCG = outCG
                }

                tileResults.append((
                    destRect: CGRect(x: srcX * scale, y: srcY * scale,
                                     width: validW, height: validH),
                    image: drawCG
                ))
            }
        }

        guard !tileResults.isEmpty else { return nil }

        // Stitch tiles onto the output canvas
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outW, height: outH),
            format: format
        )
        return renderer.image { _ in
            for tile in tileResults {
                UIImage(cgImage: tile.image).draw(in: tile.destRect)
            }
        }
    }

    /// Pad a sub-tile to 256×256 for model input.
    /// Stretches the tile to fill (approximate edge extension), then overdraws
    /// the tile at actual size in the top-left corner.
    private static func padTileToModelSize(_ tile: CGImage) -> CGImage? {
        let w = tile.width
        let h = tile.height
        let target = modelInputSize

        guard let ctx = CGContext(
            data: nil,
            width: target, height: target,
            bitsPerComponent: 8,
            bytesPerRow: target * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // Fill entire canvas by stretching the tile (extends edges approximately)
        ctx.interpolationQuality = .none
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: target, height: target))

        // Overdraw at actual size in the top-left corner
        // CGContext origin is bottom-left, so top-left = (0, target - h)
        ctx.interpolationQuality = .high
        ctx.draw(tile, in: CGRect(x: 0, y: target - h, width: w, height: h))

        return ctx.makeImage()
    }

    // MARK: - Model inference

    private static func runModel(_ model: MLModel, input cgImage: CGImage) -> UIImage? {
        let inputDescs  = model.modelDescription.inputDescriptionsByName
        let outputDescs = model.modelDescription.outputDescriptionsByName

        guard let (inputName, inputFeatureDesc) = inputDescs.first,
              let (outputName, _) = outputDescs.first else { return nil }

        // Build input feature value — handle both Image and MultiArray types
        let inputFeature: MLFeatureValue
        if inputFeatureDesc.type == .image,
           let constraint = inputFeatureDesc.imageConstraint {
            guard let fv = try? MLFeatureValue(cgImage: cgImage, constraint: constraint) else { return nil }
            inputFeature = fv
        } else {
            guard let array = cgImageToMultiArray(cgImage) else { return nil }
            inputFeature = MLFeatureValue(multiArray: array)
        }

        // Run prediction
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: inputFeature]),
              let prediction = try? model.prediction(from: provider) else { return nil }

        // Read output — handle both Image and MultiArray types
        guard let outputValue = prediction.featureValue(for: outputName) else { return nil }

        if outputValue.type == .image, let pixelBuffer = outputValue.imageBufferValue {
            return uiImageFromPixelBuffer(pixelBuffer)
        } else if let outputArray = outputValue.multiArrayValue {
            return multiArrayToUIImage(outputArray)
        }

        return nil
    }

    // MARK: - Format conversion helpers

    /// Resize to exact pixel dimensions (scale=1, orientation-safe).
    private static func resizeToPixels(_ image: UIImage, width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Convert CGImage → MLMultiArray [1, 3, H, W] float32 in [0, 1].
    private static func cgImageToMultiArray(_ cgImage: CGImage) -> MLMultiArray? {
        let width  = cgImage.width
        let height = cgImage.height

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let array = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        ) else { return nil }

        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: 3 * height * width)
        let planeSize = height * width

        for i in 0..<planeSize {
            let base = i * 4
            ptr[0 * planeSize + i] = Float32(pixels[base])     / 255.0  // R
            ptr[1 * planeSize + i] = Float32(pixels[base + 1]) / 255.0  // G
            ptr[2 * planeSize + i] = Float32(pixels[base + 2]) / 255.0  // B
        }

        return array
    }

    /// Convert MLMultiArray [1, 3, H, W] → UIImage.
    private static func multiArrayToUIImage(_ array: MLMultiArray) -> UIImage? {
        let shape = array.shape.map { $0.intValue }
        guard shape.count == 4, shape[1] == 3 else { return nil }
        let height = shape[2]
        let width  = shape[3]

        let strides = array.strides.map { $0.intValue }
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)

        var pixels = [UInt8](repeating: 255, count: height * width * 4)

        for y in 0..<height {
            for x in 0..<width {
                let rIdx = 0 * strides[1] + y * strides[2] + x * strides[3]
                let gIdx = 1 * strides[1] + y * strides[2] + x * strides[3]
                let bIdx = 2 * strides[1] + y * strides[2] + x * strides[3]

                let r = max(0, min(1, ptr[rIdx]))
                let g = max(0, min(1, ptr[gIdx]))
                let b = max(0, min(1, ptr[bIdx]))

                let i = (y * width + x) * 4
                pixels[i]     = UInt8(r * 255 + 0.5)
                pixels[i + 1] = UInt8(g * 255 + 0.5)
                pixels[i + 2] = UInt8(b * 255 + 0.5)
                pixels[i + 3] = 255
            }
        }

        return UIImage.fromPixelData(pixels, width: width, height: height)
    }

    /// Convert CVPixelBuffer → UIImage.
    private static func uiImageFromPixelBuffer(_ buffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
