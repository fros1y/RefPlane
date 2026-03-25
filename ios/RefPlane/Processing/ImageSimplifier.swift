import UIKit
import CoreML
import CoreImage

// MARK: - Image simplification using a 4× RealESRGAN CoreML model
//
// Pipeline mirrors the web version's UltraSharp flow:
//   1. Box-downsample the input by `downscale` factor
//   2. Tile the downsampled image into 256×256 patches with overlap padding
//   3. Run each patch through the 4× super-resolution model
//   4. Stitch tiles (trimming overlap) and scale back to original dimensions
//
// Tiling follows the upstream Real-ESRGAN approach:
//   - Each tile is extracted with `tilePad` pixels of overlap on every side
//   - The whole image is pre-padded with `prePad` pixels (reflect) so edge
//     tiles have real context instead of black/stretched fill
//   - After inference, only the non-padded core of each output tile is kept
//   - This eliminates visible seams between adjacent tiles
//
// The downsample→upscale cycle replaces fine texture with AI-hallucinated
// detail, producing a simplified/smoothed version of the original image.
//
// Add RealESRGAN_x4.mlpackage (or a quantized variant) to the Xcode project.
// Download from: https://huggingface.co/marshiyar/RealESRGAN_x4_CoreML

enum ImageSimplifier {

    private static let modelInputSize = 256
    private static let modelOutputSize = 1024  // 4× input
    private static let upscaleFactor = 4

    /// Overlap padding per tile edge (pixels in input space).
    /// Matches upstream Real-ESRGAN default of 10.
    private static let tilePad = 10

    /// Pre-padding applied to the entire image before tiling (reflect).
    /// Ensures edge tiles have real context. Matches upstream default of 10.
    private static let prePad = 10

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

    // MARK: - Tile-based ML inference (upstream Real-ESRGAN approach)

    /// Process an image through the fixed-size model in overlapping tiles.
    ///
    /// Following the upstream Real-ESRGAN `tile_process()`:
    ///   1. Pre-pad the image with reflect padding so edge tiles have context
    ///   2. Split into tiles of `modelInputSize` with `tilePad` overlap
    ///   3. Run each tile through the model
    ///   4. Trim the padded overlap from each output tile
    ///   5. Place only the valid (non-overlapping) core into the output canvas
    ///   6. Remove the pre-pad region from the final output
    private static func processInTiles(_ input: CGImage, model: MLModel) -> UIImage? {
        let srcW = input.width
        let srcH = input.height
        let scale = upscaleFactor

        // Step 1: Pre-pad the image with reflect padding
        let padded: CGImage
        let paddedW: Int
        let paddedH: Int
        if prePad > 0 {
            guard let p = reflectPad(input, pad: prePad) else { return nil }
            padded = p
            paddedW = srcW + prePad * 2
            paddedH = srcH + prePad * 2
        } else {
            padded = input
            paddedW = srcW
            paddedH = srcH
        }

        let tileSize = modelInputSize
        let tilesX = max(1, Int(ceil(Double(paddedW) / Double(tileSize))))
        let tilesY = max(1, Int(ceil(Double(paddedH) / Double(tileSize))))
        let outW = paddedW * scale
        let outH = paddedH * scale

        print("[ImageSimplifier] Tiling \(paddedW)×\(paddedH) (pre-padded from \(srcW)×\(srcH)) → \(tilesX)×\(tilesY) tiles, tilePad=\(tilePad)")

        // Allocate output pixel buffer (RGBA)
        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                // Input tile area (non-padded core)
                let inputStartX = tx * tileSize
                let inputEndX   = min(inputStartX + tileSize, paddedW)
                let inputStartY = ty * tileSize
                let inputEndY   = min(inputStartY + tileSize, paddedH)

                // Input tile area with overlap padding (clamped to image bounds)
                let inputStartXPad = max(inputStartX - tilePad, 0)
                let inputEndXPad   = min(inputEndX + tilePad, paddedW)
                let inputStartYPad = max(inputStartY - tilePad, 0)
                let inputEndYPad   = min(inputEndY + tilePad, paddedH)

                let inputTileWidth  = inputEndX - inputStartX
                let inputTileHeight = inputEndY - inputStartY

                // Extract tile with padding from the pre-padded image
                guard let tileCG = padded.cropping(to: CGRect(
                    x: inputStartXPad, y: inputStartYPad,
                    width: inputEndXPad - inputStartXPad,
                    height: inputEndYPad - inputStartYPad
                )) else { continue }

                // Resize tile to model input size (256×256)
                let modelInputImage = resizeToPixels(
                    UIImage(cgImage: tileCG),
                    width: modelInputSize, height: modelInputSize
                )
                guard let modelInputCG = modelInputImage.cgImage else { continue }

                // Run model inference → 1024×1024 output
                guard let outputImage = runModel(model, input: modelInputCG),
                      let outCG = outputImage.cgImage else { continue }

                // Read output tile pixels
                let outTileW = outCG.width
                let outTileH = outCG.height
                var outTilePixels = [UInt8](repeating: 0, count: outTileW * outTileH * 4)
                guard let outCtx = CGContext(
                    data: &outTilePixels,
                    width: outTileW, height: outTileH,
                    bitsPerComponent: 8, bytesPerRow: outTileW * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else { continue }
                outCtx.draw(outCG, in: CGRect(x: 0, y: 0, width: outTileW, height: outTileH))

                // Calculate the valid region within the model output.
                // The model output maps to the padded input tile; we need to
                // find where the non-padded core sits within the output.
                let paddedTileW = inputEndXPad - inputStartXPad
                let paddedTileH = inputEndYPad - inputStartYPad

                // Scale factors from padded tile → model output
                let scaleX = Double(outTileW) / Double(paddedTileW)
                let scaleY = Double(outTileH) / Double(paddedTileH)

                // Offset of the valid core within the padded tile
                let coreOffsetX = inputStartX - inputStartXPad
                let coreOffsetY = inputStartY - inputStartYPad

                // Valid region in output tile coordinates
                let outCoreStartX = Int(round(Double(coreOffsetX) * scaleX))
                let outCoreStartY = Int(round(Double(coreOffsetY) * scaleY))
                let outCoreW = Int(round(Double(inputTileWidth) * scaleX))
                let outCoreH = Int(round(Double(inputTileHeight) * scaleY))

                // Destination in the full output image
                let destX = inputStartX * scale
                let destY = inputStartY * scale
                let destW = inputTileWidth * scale
                let destH = inputTileHeight * scale

                // Copy valid pixels from output tile → output canvas
                // (scale from outCore → dest if they differ slightly due to rounding)
                for dy in 0..<destH {
                    let srcRow = min(outCoreStartY + dy * outCoreH / destH, outTileH - 1)
                    for dx in 0..<destW {
                        let srcCol = min(outCoreStartX + dx * outCoreW / destW, outTileW - 1)

                        let srcIdx = (srcRow * outTileW + srcCol) * 4
                        let dstIdx = ((destY + dy) * outW + (destX + dx)) * 4

                        guard dstIdx + 3 < outputPixels.count,
                              srcIdx + 3 < outTilePixels.count else { continue }

                        outputPixels[dstIdx]     = outTilePixels[srcIdx]
                        outputPixels[dstIdx + 1] = outTilePixels[srcIdx + 1]
                        outputPixels[dstIdx + 2] = outTilePixels[srcIdx + 2]
                        outputPixels[dstIdx + 3] = 255
                    }
                }
            }
        }

        // Step 6: Remove pre-pad from the output
        let finalW = srcW * scale
        let finalH = srcH * scale
        let prePadScaled = prePad * scale

        guard let fullImage = UIImage.fromPixelData(outputPixels, width: outW, height: outH),
              let fullCG = fullImage.cgImage else { return nil }

        if prePad > 0 {
            guard let cropped = fullCG.cropping(to: CGRect(
                x: prePadScaled, y: prePadScaled,
                width: finalW, height: finalH
            )) else { return nil }
            return UIImage(cgImage: cropped)
        }

        return fullImage
    }

    /// Reflect-pad an image on all four sides.
    ///
    /// Mirrors `F.pad(img, (pad, pad, pad, pad), 'reflect')` from the upstream
    /// Real-ESRGAN pre_process step. This gives edge tiles real mirrored context
    /// instead of black borders or stretched content.
    private static func reflectPad(_ image: CGImage, pad: Int) -> CGImage? {
        let w = image.width
        let h = image.height
        let newW = w + pad * 2
        let newH = h + pad * 2

        // Read source pixels
        var srcPixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let srcCtx = CGContext(
            data: &srcPixels,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        srcCtx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Build padded image with reflected edges
        var dstPixels = [UInt8](repeating: 0, count: newW * newH * 4)

        for dy in 0..<newH {
            // Reflect Y: map destination row → source row
            var sy = dy - pad
            if sy < 0 { sy = -sy }
            if sy >= h { sy = 2 * h - sy - 2 }
            sy = max(0, min(h - 1, sy))

            for dx in 0..<newW {
                // Reflect X: map destination col → source col
                var sx = dx - pad
                if sx < 0 { sx = -sx }
                if sx >= w { sx = 2 * w - sx - 2 }
                sx = max(0, min(w - 1, sx))

                let srcIdx = (sy * w + sx) * 4
                let dstIdx = (dy * newW + dx) * 4
                dstPixels[dstIdx]     = srcPixels[srcIdx]
                dstPixels[dstIdx + 1] = srcPixels[srcIdx + 1]
                dstPixels[dstIdx + 2] = srcPixels[srcIdx + 2]
                dstPixels[dstIdx + 3] = 255
            }
        }

        guard let dstCtx = CGContext(
            data: &dstPixels,
            width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: newW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // Force render — CGContext data pointer is our dstPixels
        return dstCtx.makeImage()
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
