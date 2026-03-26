import UIKit
import CoreML
import CoreImage

// MARK: - Simplification errors

enum SimplificationError: LocalizedError {
    case modelUnavailable(SimplificationMethod)
    case unsupportedModelContract(SimplificationMethod)
    case inferenceFailed(SimplificationMethod)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let m):
            return "Model for \(m.label) is not available in this build."
        case .unsupportedModelContract(let m):
            return "Model for \(m.label) does not satisfy the required runtime contract."
        case .inferenceFailed(let m):
            return "Inference failed for \(m.label)."
        }
    }
}

// MARK: - Actor-backed model cache

private actor SimplificationModelStore {
    private var cachedModels: [SimplificationMethod: MLModel] = [:]

    func model(for method: SimplificationMethod) -> MLModel? { cachedModels[method] }
    func insert(_ model: MLModel, for method: SimplificationMethod) { cachedModels[method] = model }
    func clear() { cachedModels.removeAll() }
}

// MARK: - Image simplification pipeline
//
// Unified pipeline for all methods:
//   source image (already capped to max 1600 px)
//     -> downsample by strength factor (2x to 12x)
//     -> method-specific processing
//     -> resize back to original dimensions
//
// Tiling follows the upstream Real-ESRGAN approach for 4× SR methods:
//   - Each tile is extracted with `tilePad` pixels of overlap on every side
//   - The whole image is pre-padded with `prePad` pixels (reflect) so edge
//     tiles have real context instead of black/stretched fill
//   - After inference, only the non-padded core of each output tile is kept
//   - This eliminates visible seams between adjacent tiles

enum ImageSimplifier {

    private static let modelInputSize = 256
    private static let modelOutputSize = 1024  // 4× input
    private static let upscaleFactor = 4

    /// Overlap padding per tile edge (pixels in input space).
    private static let tilePad = 10

    /// Pre-padding applied to the entire image before tiling (reflect).
    private static let prePad = 10

    // MARK: - Model cache

    private static let modelStore = SimplificationModelStore()

    /// Evict all loaded models. Call this on memory warning.
    static func clearModelCache() {
        Task { await modelStore.clear() }
    }

    // MARK: - Model loading

    private static func loadModel(for method: SimplificationMethod) async throws -> MLModel {
        if let cached = await modelStore.model(for: method) { return cached }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        guard let name = method.modelBundleName else {
            throw SimplificationError.modelUnavailable(method)
        }
        let candidates = [name]

        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
               let model = try? MLModel(contentsOf: url, configuration: config) {
                print("[ImageSimplifier] Loaded compiled model: \(name).mlmodelc")
                await modelStore.insert(model, for: method)
                return model
            }

            if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                if let compiledURL = try? await MLModel.compileModel(at: url),
                   let model = try? MLModel(contentsOf: compiledURL, configuration: config) {
                    print("[ImageSimplifier] Compiled and loaded: \(name).mlpackage")
                    await modelStore.insert(model, for: method)
                    return model
                }
            }

            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodel") {
                if let compiledURL = try? await MLModel.compileModel(at: url),
                   let model = try? MLModel(contentsOf: compiledURL, configuration: config) {
                    print("[ImageSimplifier] Compiled and loaded: \(name).mlmodel")
                    await modelStore.insert(model, for: method)
                    return model
                }
            }
        }

        print("[ImageSimplifier] No model found for \(method.label)")
        throw SimplificationError.modelUnavailable(method)
    }

    // MARK: - Public API

    /// Simplify an image using the specified method.
    ///
    /// - Parameters:
    ///   - image: The source image (already capped to max 1600 px).
    ///   - downscale: Downsample factor before processing (2–12).
    ///   - method: The simplification method to apply.
    ///   - onProgress: Optional closure called with a 0–1 progress fraction as tiles complete.
    ///                 Called from a background thread; hop to main actor if needed.
    /// - Throws: `SimplificationError` if the model is unavailable or inference fails.
    /// - Returns: The simplified image at the original dimensions.
    static func simplify(
        image: UIImage,
        downscale: CGFloat = 4.0,
        method: SimplificationMethod = .apisr,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> UIImage {
        guard let sourceCG = image.cgImage else {
            throw SimplificationError.inferenceFailed(method)
        }
        let origW = sourceCG.width
        let origH = sourceCG.height

        // Load model (async) before entering the detached compute task
        let loadedModel: MLModel?
        switch method.processingKind {
        case .superResolution4x, .fullImageModel:
            loadedModel = try await loadModel(for: method)
        case .metalShader:
            loadedModel = nil
        }

        let metalCtx = (method.processingKind == .metalShader) ? MetalContext.shared : nil
        if method.processingKind == .metalShader && metalCtx == nil {
            throw SimplificationError.inferenceFailed(method)
        }

        return try await Task.detached(priority: .userInitiated) {
            let smallW = max(1, Int(round(Double(origW) / Double(downscale))))
            let smallH = max(1, Int(round(Double(origH) / Double(downscale))))
            let small = resizeToPixels(image, width: smallW, height: smallH)

            switch method.processingKind {
            case .superResolution4x:
                guard let model = loadedModel,
                      let smallCG = small.cgImage,
                      let upscaled = processInTiles(smallCG, model: model, onProgress: onProgress) else {
                    throw SimplificationError.inferenceFailed(method)
                }
                return resizeToPixels(upscaled, width: origW, height: origH)

            case .fullImageModel:
                guard let model = loadedModel,
                      let smallCG = small.cgImage,
                      let result = runModel(model, input: smallCG) else {
                    throw SimplificationError.inferenceFailed(method)
                }
                return resizeToPixels(result, width: origW, height: origH)

            case .metalShader:
                guard let ctx = metalCtx,
                      let smallCG = small.cgImage,
                      let result = ctx.anisotropicKuwahara(smallCG) else {
                    throw SimplificationError.inferenceFailed(method)
                }
                return resizeToPixels(result, width: origW, height: origH)
            }
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
    private static func processInTiles(_ input: CGImage, model: MLModel, onProgress: ((Double) -> Void)? = nil) -> UIImage? {
        let srcW = input.width
        let srcH = input.height
        let scale = upscaleFactor

        let tileSize = modelInputSize
        let coreW = srcW + prePad * 2
        let coreH = srcH + prePad * 2
        let extraRight = (tileSize - (coreW % tileSize)) % tileSize
        let extraBottom = (tileSize - (coreH % tileSize)) % tileSize
        let alignedCoreW = coreW + extraRight
        let alignedCoreH = coreH + extraBottom

        guard let prePadded = reflectPad(input,
                                         left: prePad,
                                         right: prePad + extraRight,
                                         top: prePad,
                                         bottom: prePad + extraBottom),
              let workingImage = reflectPad(prePadded,
                                            left: tilePad,
                                            right: tilePad,
                                            top: tilePad,
                                            bottom: tilePad) else {
            return nil
        }

        let tilesX = max(1, alignedCoreW / tileSize)
        let tilesY = max(1, alignedCoreH / tileSize)
        let outW = alignedCoreW * scale
        let outH = alignedCoreH * scale
        let paddedTileSize = tileSize + tilePad * 2

        print("[ImageSimplifier] Tiling \(alignedCoreW)×\(alignedCoreH) (aligned from \(srcW)×\(srcH)) → \(tilesX)×\(tilesY) tiles, tilePad=\(tilePad)")

        // Allocate output pixel buffer (RGBA)
        var outputPixels = [UInt8](repeating: 0, count: outW * outH * 4)

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                // Input tile area (non-padded core)
                let inputStartX = tx * tileSize
                let inputEndX   = inputStartX + tileSize
                let inputStartY = ty * tileSize
                let inputEndY   = inputStartY + tileSize

                let inputTileWidth  = inputEndX - inputStartX
                let inputTileHeight = inputEndY - inputStartY

                // Extract a fixed-size tile including overlap from the aligned canvas.
                guard let tileCG = workingImage.cropping(to: CGRect(
                    x: inputStartX,
                    y: inputStartY,
                    width: paddedTileSize,
                    height: paddedTileSize
                )) else { continue }

                let tileImage = resizeToPixels(
                    UIImage(cgImage: tileCG),
                    width: modelInputSize, height: modelInputSize
                )
                guard let modelInputCG = tileImage.cgImage else { continue }

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
                // Scale factors from the resized padded tile space → model output.
                // The extracted tile includes `tilePad` context on each side and is
                // resized down to the fixed model input size before inference, so the
                // valid crop must be mapped from padded-tile coordinates rather than
                // assuming the whole 256px model input is usable core content.
                let scaleX = Double(outTileW) / Double(paddedTileSize)
                let scaleY = Double(outTileH) / Double(paddedTileSize)

                // Offset of the valid core within the padded tile.
                let coreOffsetX = tilePad
                let coreOffsetY = tilePad

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

                // Report tile-based progress
                let completedTiles = ty * tilesX + tx + 1
                onProgress?(Double(completedTiles) / Double(tilesX * tilesY))
            }
        }

        // Step 6: Remove alignment padding and pre-pad from the output
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
        reflectPad(image, left: pad, right: pad, top: pad, bottom: pad)
    }

    private static func reflectPad(
        _ image: CGImage,
        left: Int,
        right: Int,
        top: Int,
        bottom: Int
    ) -> CGImage? {
        let w = image.width
        let h = image.height
        let newW = w + left + right
        let newH = h + top + bottom
        guard w > 0, h > 0, newW > 0, newH > 0 else { return nil }

        var srcPixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let srcCtx = CGContext(
            data: &srcPixels,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        srcCtx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var dstPixels = [UInt8](repeating: 0, count: newW * newH * 4)

        for dy in 0..<newH {
            let sy = reflectedCoordinate(dy - top, limit: h)
            for dx in 0..<newW {
                let sx = reflectedCoordinate(dx - left, limit: w)
                let srcIdx = (sy * w + sx) * 4
                let dstIdx = (dy * newW + dx) * 4
                dstPixels[dstIdx] = srcPixels[srcIdx]
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
        return dstCtx.makeImage()
    }

    private static func reflectedCoordinate(_ coordinate: Int, limit: Int) -> Int {
        guard limit > 1 else { return 0 }
        var value = coordinate
        while value < 0 || value >= limit {
            if value < 0 {
                value = -value
            } else {
                value = 2 * limit - value - 2
            }
        }
        return max(0, min(limit - 1, value))
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
