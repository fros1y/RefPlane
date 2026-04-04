import Metal
import UIKit

// MARK: - GPU compute context for image processing

/// Singleton Metal context — initializes device, command queue, and all compute
/// pipelines from the compiled .metal shader library. Falls back gracefully to
/// CPU processing when Metal is unavailable.
final class MetalContext {

    static let shared: MetalContext? = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[MetalContext] ⚠️ MTLCreateSystemDefaultDevice() returned nil — no GPU available")
            return nil
        }
        print("[MetalContext] ✅ Metal device: \(device.name)")
        let ctx = MetalContext(device: device)
        if ctx == nil {
            print("[MetalContext] ⚠️ MetalContext init failed (library or pipeline error)")
        } else {
            print("[MetalContext] ✅ All 15 compute pipelines compiled successfully")
        }
        return ctx
    }()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary

    // Compiled pipeline states
    let grayscalePipeline: MTLComputePipelineState
    let rgbToOklabPipeline: MTLComputePipelineState
    let bandAssignPipeline: MTLComputePipelineState
    let colorBuildLabelsPipeline: MTLComputePipelineState
    let colorHistogramPipeline: MTLComputePipelineState
    let kmeansAssignPipeline: MTLComputePipelineState
    let quantizePipeline: MTLComputePipelineState
    let remapByLabelPipeline: MTLComputePipelineState
    let valueRemapPipeline: MTLComputePipelineState
    let kuwaharaStructureTensorPipeline: MTLComputePipelineState
    let kuwaharaFilterPipeline: MTLComputePipelineState
    let depthEffectsPipeline: MTLComputePipelineState
    let depthGaussianBlurHPipeline: MTLComputePipelineState
    let depthGaussianBlurVPipeline: MTLComputePipelineState
    let depthRemoveBackgroundPipeline: MTLComputePipelineState

    private init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let lib = device.makeDefaultLibrary() else { return nil }
        self.commandQueue = queue
        self.library = lib

        do {
            grayscalePipeline              = try Self.makePipeline(device: device, library: lib, name: "grayscale")
            rgbToOklabPipeline             = try Self.makePipeline(device: device, library: lib, name: "rgb_to_oklab")
            bandAssignPipeline             = try Self.makePipeline(device: device, library: lib, name: "band_assign")
            colorBuildLabelsPipeline       = try Self.makePipeline(device: device, library: lib, name: "color_build_labels")
            colorHistogramPipeline         = try Self.makePipeline(device: device, library: lib, name: "color_histogram")
            kmeansAssignPipeline           = try Self.makePipeline(device: device, library: lib, name: "kmeans_assign")
            quantizePipeline               = try Self.makePipeline(device: device, library: lib, name: "quantize")
            remapByLabelPipeline           = try Self.makePipeline(device: device, library: lib, name: "remap_by_label")
            valueRemapPipeline             = try Self.makePipeline(device: device, library: lib, name: "value_remap")
            kuwaharaStructureTensorPipeline = try Self.makePipeline(device: device, library: lib, name: "kuwahara_structure_tensor")
            kuwaharaFilterPipeline          = try Self.makePipeline(device: device, library: lib, name: "kuwahara_filter")
            depthEffectsPipeline            = try Self.makePipeline(device: device, library: lib, name: "depth_painterly_effects")
            depthGaussianBlurHPipeline      = try Self.makePipeline(device: device, library: lib, name: "depth_gaussian_blur_h")
            depthGaussianBlurVPipeline      = try Self.makePipeline(device: device, library: lib, name: "depth_gaussian_blur_v")
            depthRemoveBackgroundPipeline   = try Self.makePipeline(device: device, library: lib, name: "depth_remove_background")
        } catch {
            print("[MetalContext] Pipeline creation failed: \(error)")
            return nil
        }
    }

    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        name: String
    ) throws -> MTLComputePipelineState {
        guard let fn = library.makeFunction(name: name) else {
            throw MetalError.functionNotFound(name)
        }
        return try device.makeComputePipelineState(function: fn)
    }

    // MARK: - Buffer helpers

    func makeBuffer<T>(_ data: [T]) -> MTLBuffer? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { bufferPtr in
            device.makeBuffer(bytes: bufferPtr.baseAddress!, length: bufferPtr.count, options: .storageModeShared)
        }
    }

    func makeBuffer(length: Int) -> MTLBuffer? {
        device.makeBuffer(length: max(4, length), options: .storageModeShared)
    }

    // MARK: - Dispatch helper

    /// Encode and commit a single compute pass, wait for completion.
    func dispatch(
        pipeline: MTLComputePipelineState,
        buffers: [(MTLBuffer, Int)],
        gridSize: Int
    ) {
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        for (buffer, index) in buffers {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }

        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, 64)
        let threadGroups = (gridSize + threadGroupSize - 1) / threadGroupSize
        encoder.dispatchThreadgroups(
            MTLSize(width: threadGroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadGroupSize, height: 1, depth: 1)
        )
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }

    // MARK: - Pixel buffer helpers

    /// Create a Metal buffer from raw RGBA pixel bytes.
    /// On little-endian ARM (all Apple platforms), [R,G,B,A] bytes are
    /// identical in memory to the packed uint32 that shaders expect.
    func makePixelBuffer(_ rgba: [UInt8]) -> MTLBuffer? {
        guard !rgba.isEmpty else { return nil }
        return device.makeBuffer(bytes: rgba, length: rgba.count, options: .storageModeShared)
    }

    /// Read packed RGBA output from a Metal buffer as raw [UInt8].
    func readPixels(from buffer: MTLBuffer, count: Int) -> [UInt8] {
        let byteCount = count * 4
        let ptr = buffer.contents().assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: ptr, count: byteCount))
    }

    // MARK: - High-level operations

    /// Grayscale conversion on GPU. Returns nil on failure.
    func processGrayscale(pixels: [UInt8], width: Int, height: Int) -> [UInt8]? {
        let count = width * height

        guard let srcBuf = makePixelBuffer(pixels),
              let dstBuf = makeBuffer(length: count * 4) else { return nil }

        var params = GrayscaleParamsSwift(pixelCount: UInt32(count))
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<GrayscaleParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        dispatch(pipeline: grayscalePipeline,
                 buffers: [(srcBuf, 0), (dstBuf, 1), (paramBuf, 2)],
                 gridSize: count)

        return readPixels(from: dstBuf, count: count)
    }

    /// RGB → Oklab on GPU. Returns interleaved [Float] lab array, the source pixel MTLBuffer,
    /// and the lab MTLBuffer (reusable by assignBands and kmeansAssign).
    func rgbToOklab(pixels: [UInt8], width: Int, height: Int) -> (lab: [Float], srcBuffer: MTLBuffer, labBuffer: MTLBuffer)? {
        let count = width * height

        guard let srcBuf = makePixelBuffer(pixels),
              let labBuf = makeBuffer(length: count * 3 * MemoryLayout<Float>.stride) else { return nil }

        var params = RGBToOklabParamsSwift(pixelCount: UInt32(count))
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<RGBToOklabParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        dispatch(pipeline: rgbToOklabPipeline,
                 buffers: [(srcBuf, 0), (labBuf, 1), (paramBuf, 2)],
                 gridSize: count)

        let labPtr = labBuf.contents().bindMemory(to: Float.self, capacity: count * 3)
        let labArray = Array(UnsafeBufferPointer(start: labPtr, count: count * 3))
        return (labArray, srcBuf, labBuf)
    }

    /// Assign each pixel to a luminance band. Accepts lab MTLBuffer to avoid re-upload.
    /// Returns [Int32] of band indices.
    func assignBands(labBuffer: MTLBuffer, count: Int, thresholds: [Float], totalBands: Int) -> [Int32]? {
        guard let bandBuf = makeBuffer(length: count * MemoryLayout<Int32>.stride),
              let threshBuf = makeBuffer(thresholds) else { return nil }

        var params = BandAssignParamsSwift(
            pixelCount: UInt32(count),
            thresholdCount: UInt32(thresholds.count),
            totalBands: UInt32(totalBands)
        )
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<BandAssignParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        dispatch(pipeline: bandAssignPipeline,
                 buffers: [(labBuffer, 0), (bandBuf, 1), (paramBuf, 2), (threshBuf, 3)],
                 gridSize: count)

        let ptr = bandBuf.contents().bindMemory(to: Int32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    /// K-Means assignment step on GPU. Accepts pre-uploaded pixel lab MTLBuffer.
    /// Returns [UInt32] cluster assignments.
    func kmeansAssign(pixelLabBuffer: MTLBuffer, count: Int, centroidLab: [Float], k: Int, lWeight: Float) -> [UInt32]? {
        guard let centBuf = makeBuffer(centroidLab),
              let assignBuf = makeBuffer(length: count * MemoryLayout<UInt32>.stride) else { return nil }

        var params = KMeansAssignParamsSwift(
            numPixels: UInt32(count),
            k: UInt32(k),
            lWeight: lWeight
        )
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<KMeansAssignParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        dispatch(pipeline: kmeansAssignPipeline,
                 buffers: [(pixelLabBuffer, 0), (centBuf, 1), (assignBuf, 2), (paramBuf, 3)],
                 gridSize: count)

        let ptr = assignBuf.contents().bindMemory(to: UInt32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    /// Build color-study labels from family assignments + Oklab-L thresholds.
    func buildColorLabels(
        labBuffer: MTLBuffer,
        familyAssignments: [UInt32],
        count: Int,
        familyCount: Int,
        valuesPerFamily: Int,
        thresholds: [Float]
    ) -> [Int32]? {
        guard let assignmentBuffer = makeBuffer(familyAssignments),
              let labelBuffer = makeBuffer(length: count * MemoryLayout<Int32>.stride),
              let thresholdBuffer = makeBuffer(thresholds) else { return nil }

        var params = ColorLabelParamsSwift(
            pixelCount: UInt32(count),
            familyCount: UInt32(familyCount),
            thresholdCount: UInt32(thresholds.count),
            valuesPerFamily: UInt32(valuesPerFamily)
        )
        guard let paramBuf = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<ColorLabelParamsSwift>.stride,
            options: .storageModeShared
        ) else { return nil }

        dispatch(
            pipeline: colorBuildLabelsPipeline,
            buffers: [(labBuffer, 0), (assignmentBuffer, 1), (labelBuffer, 2), (paramBuf, 3), (thresholdBuffer, 4)],
            gridSize: count
        )

        let ptr = labelBuffer.contents().bindMemory(to: Int32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    /// Build a coarse Oklab histogram on the GPU and return bin counts + summed components.
    func buildColorHistogram(
        labBuffer: MTLBuffer,
        count: Int,
        lBins: Int,
        aBins: Int,
        bBins: Int,
        aMin: Float,
        aMax: Float,
        bMin: Float,
        bMax: Float
    ) -> (counts: [UInt32], sumL: [UInt32], sumA: [UInt32], sumB: [UInt32])? {
        let totalBins = lBins * aBins * bBins
        let zeroes = [UInt32](repeating: 0, count: totalBins)

        guard let countBuffer = makeBuffer(zeroes),
              let sumLBuffer = makeBuffer(zeroes),
              let sumABuffer = makeBuffer(zeroes),
              let sumBBuffer = makeBuffer(zeroes) else { return nil }

        var params = ColorHistogramParamsSwift(
            pixelCount: UInt32(count),
            lBins: UInt32(lBins),
            aBins: UInt32(aBins),
            bBins: UInt32(bBins),
            aMin: aMin,
            aMax: aMax,
            bMin: bMin,
            bMax: bMax
        )
        guard let paramBuf = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<ColorHistogramParamsSwift>.stride,
            options: .storageModeShared
        ) else { return nil }

        dispatch(
            pipeline: colorHistogramPipeline,
            buffers: [(labBuffer, 0), (countBuffer, 1), (sumLBuffer, 2), (sumABuffer, 3), (sumBBuffer, 4), (paramBuf, 5)],
            gridSize: count
        )

        let countsPtr = countBuffer.contents().bindMemory(to: UInt32.self, capacity: totalBins)
        let sumLPtr = sumLBuffer.contents().bindMemory(to: UInt32.self, capacity: totalBins)
        let sumAPtr = sumABuffer.contents().bindMemory(to: UInt32.self, capacity: totalBins)
        let sumBPtr = sumBBuffer.contents().bindMemory(to: UInt32.self, capacity: totalBins)

        return (
            counts: Array(UnsafeBufferPointer(start: countsPtr, count: totalBins)),
            sumL: Array(UnsafeBufferPointer(start: sumLPtr, count: totalBins)),
            sumA: Array(UnsafeBufferPointer(start: sumAPtr, count: totalBins)),
            sumB: Array(UnsafeBufferPointer(start: sumBPtr, count: totalBins))
        )
    }

    /// Quantize + label map on GPU. Returns (srcBuffer, labelMap [Int32]).
    /// The srcBuffer is the uploaded pixel data — reuse it for valueRemap.
    func quantize(pixels: [UInt8], width: Int, height: Int,
                  thresholds: [Float], totalLevels: Int) -> (srcBuffer: MTLBuffer, labels: [Int32])? {
        let count = width * height

        guard let srcBuf  = makePixelBuffer(pixels),
              let dstBuf  = makeBuffer(length: count * 4),
              let thBuf   = makeBuffer(thresholds),
              let lblBuf  = makeBuffer(length: count * MemoryLayout<Int32>.stride) else { return nil }

        var params = QuantizeParamsSwift(
            pixelCount: UInt32(count),
            thresholdCount: UInt32(thresholds.count),
            totalLevels: UInt32(totalLevels)
        )
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<QuantizeParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        dispatch(pipeline: quantizePipeline,
                 buffers: [(srcBuf, 0), (dstBuf, 1), (paramBuf, 2), (thBuf, 3), (lblBuf, 4)],
                 gridSize: count)

        let lblPtr = lblBuf.contents().bindMemory(to: Int32.self, capacity: count)
        let lblArr = Array(UnsafeBufferPointer(start: lblPtr, count: count))

        return (srcBuf, lblArr)
    }

    /// Remap pixels by label → Oklab centroids. Accepts a source pixel MTLBuffer
    /// (from rgbToOklab) to avoid re-uploading. Returns [UInt8] RGBA.
    func remapByLabel(srcBuffer: MTLBuffer, labels: [Int32], centroids: [Float],
                      count: Int) -> [UInt8]? {
        guard let lblBuf  = makeBuffer(labels),
              let centBuf = makeBuffer(centroids),
              let dstBuf  = makeBuffer(length: count * 4) else { return nil }

        var params = RemapParamsSwift(
            pixelCount: UInt32(count),
            centroidCount: UInt32(centroids.count / 3)
        )
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<RemapParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        dispatch(pipeline: remapByLabelPipeline,
                 buffers: [(srcBuffer, 0), (lblBuf, 1), (centBuf, 2), (dstBuf, 3), (paramBuf, 4)],
                 gridSize: count)

        return readPixels(from: dstBuf, count: count)
    }

    /// Re-render label map to evenly-spaced value grays after region cleanup.
    /// Accepts the srcBuffer from quantize() to avoid re-uploading pixels.
    func valueRemap(srcBuffer: MTLBuffer, labels: [Int32], count: Int, totalLevels: Int) -> [UInt8]? {
        guard let lblBuf = makeBuffer(labels),
              let dstBuf = makeBuffer(length: count * 4) else { return nil }

        var params = ValueRemapParamsSwift(
            pixelCount: UInt32(count),
            totalLevels: UInt32(totalLevels)
        )
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<ValueRemapParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        dispatch(pipeline: valueRemapPipeline,
                 buffers: [(srcBuffer, 0), (lblBuf, 1), (dstBuf, 2), (paramBuf, 3)],
                 gridSize: count)

        return readPixels(from: dstBuf, count: count)
    }

    // MARK: - Anisotropic Kuwahara (texture-based)

    /// Apply the anisotropic Kuwahara filter to a CGImage.
    /// Uses two texture-based compute passes (structure tensor + filter).
    /// - Parameters:
    ///   - image: Source image (any size; typically the downsampled simplification input).
    ///   - radius: Kuwahara neighbourhood radius (default 6).
    /// - Returns: Filtered UIImage of the same pixel dimensions, or nil on failure.
    func anisotropicKuwahara(_ image: CGImage, radius: Int = 6) -> UIImage? {
        let width  = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        // Build a Metal texture descriptor for RGBA float textures (intermediate)
        let floatDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width, height: height,
            mipmapped: false
        )
        floatDesc.usage = [.shaderRead, .shaderWrite]
        floatDesc.storageMode = .private

        // BGRA unorm descriptor for source and output
        let rgbaDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        rgbaDesc.usage = [.shaderRead, .shaderWrite]
        rgbaDesc.storageMode = .shared

        guard let srcTex    = makeTextureFromCGImage(image),
              let tensorTex = device.makeTexture(descriptor: floatDesc),
              let dstTex    = device.makeTexture(descriptor: rgbaDesc) else { return nil }

        // Build params buffer (shared for both passes)
        var params = KuwaharaParamsSwift(
            width: UInt32(width),
            height: UInt32(height),
            radius: Int32(radius)
        )
        guard let paramBuf = device.makeBuffer(bytes: &params,
                                               length: MemoryLayout<KuwaharaParamsSwift>.stride,
                                               options: .storageModeShared) else { return nil }

        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }

        // Pass 1: structure tensor
        if let encoder = cmdBuf.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(kuwaharaStructureTensorPipeline)
            encoder.setTexture(srcTex,    index: 0)
            encoder.setTexture(tensorTex, index: 1)
            encoder.setBuffer(paramBuf, offset: 0, index: 0)
            let tgs = MTLSize(width: 8, height: 8, depth: 1)
            let grd = MTLSize(
                width:  (width  + 7) / 8,
                height: (height + 7) / 8,
                depth:  1
            )
            encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
            encoder.endEncoding()
        }

        // Pass 2: Kuwahara filter
        if let encoder = cmdBuf.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(kuwaharaFilterPipeline)
            encoder.setTexture(srcTex,    index: 0)
            encoder.setTexture(tensorTex, index: 1)
            encoder.setTexture(dstTex,    index: 2)
            encoder.setBuffer(paramBuf, offset: 0, index: 0)
            let tgs = MTLSize(width: 8, height: 8, depth: 1)
            let grd = MTLSize(
                width:  (width  + 7) / 8,
                height: (height + 7) / 8,
                depth:  1
            )
            encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
            encoder.endEncoding()
        }

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return uiImageFromTexture(dstTex, width: width, height: height)
    }

    // MARK: - Depth-based painterly effects (texture-based)

    /// Apply depth-based atmospheric perspective effects to a source image.
    /// - Parameters:
    ///   - source: The mode-processed (or original) image.
    ///   - depthMap: Single-channel grayscale depth map (0=near, 1=far), same dimensions.
    ///   - config: Depth effect configuration (cutoffs, intensity, mode).
    /// - Returns: Composited UIImage with depth effects applied, or nil on failure.
    func applyDepthEffects(_ source: CGImage, depthMap: CGImage, config: DepthConfig) -> UIImage? {
        let width  = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        guard let srcTex = makeTextureFromCGImage(source),
              let depthTex = makeGrayscaleTexture(depthMap, width: width, height: height) else { return nil }

        // BGRA unorm descriptor for intermediate + output
        let rgbaDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        rgbaDesc.usage = [.shaderRead, .shaderWrite]
        rgbaDesc.storageMode = .shared

        var params = DepthEffectParamsSwift(
            width: UInt32(width),
            height: UInt32(height),
            foregroundCutoff: Float(config.foregroundCutoff),
            backgroundCutoff: Float(config.backgroundCutoff),
            intensity: Float(config.effectIntensity),
            backgroundMode: UInt32(backgroundModeRaw(config.backgroundMode))
        )
        guard let paramBuf = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<DepthEffectParamsSwift>.stride,
            options: .storageModeShared
        ) else { return nil }

        let tgs = MTLSize(width: 8, height: 8, depth: 1)
        let grd = MTLSize(
            width:  (width  + 7) / 8,
            height: (height + 7) / 8,
            depth:  1
        )

        // Choose processing path based on background mode
        switch config.backgroundMode {
        case .none:
            return uiImageFromTexture(srcTex, width: width, height: height)

        case .blur:
            // Step 1: Horizontal blur pass
            guard let tmpTex = device.makeTexture(descriptor: rgbaDesc),
                  let dstTex = device.makeTexture(descriptor: rgbaDesc) else { return nil }

            guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }

            if let encoder = cmdBuf.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(depthGaussianBlurHPipeline)
                encoder.setTexture(srcTex,   index: 0)
                encoder.setTexture(depthTex, index: 1)
                encoder.setTexture(tmpTex,   index: 2)
                encoder.setBuffer(paramBuf, offset: 0, index: 0)
                encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
                encoder.endEncoding()
            }

            // Step 2: Vertical blur pass
            guard let blurredTex = device.makeTexture(descriptor: rgbaDesc) else { return nil }

            if let encoder = cmdBuf.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(depthGaussianBlurVPipeline)
                encoder.setTexture(tmpTex,   index: 0)
                encoder.setTexture(depthTex, index: 1)
                encoder.setTexture(blurredTex, index: 2)
                encoder.setBuffer(paramBuf, offset: 0, index: 0)
                encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
                encoder.endEncoding()
            }

            // Step 3: Apply painterly effects on blurred result
            if let encoder = cmdBuf.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(depthEffectsPipeline)
                encoder.setTexture(blurredTex, index: 0)
                encoder.setTexture(depthTex,   index: 1)
                encoder.setTexture(dstTex,     index: 2)
                encoder.setBuffer(paramBuf, offset: 0, index: 0)
                encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
                encoder.endEncoding()
            }

            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            return uiImageFromTexture(dstTex, width: width, height: height)

        case .remove:
            // Step 1: Remove background (white fill)
            guard let removedTex = device.makeTexture(descriptor: rgbaDesc),
                  let dstTex = device.makeTexture(descriptor: rgbaDesc) else { return nil }

            guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }

            if let encoder = cmdBuf.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(depthRemoveBackgroundPipeline)
                encoder.setTexture(srcTex,   index: 0)
                encoder.setTexture(depthTex, index: 1)
                encoder.setTexture(removedTex, index: 2)
                encoder.setBuffer(paramBuf, offset: 0, index: 0)
                encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
                encoder.endEncoding()
            }

            // Step 2: Apply painterly effects on remaining foreground
            if let encoder = cmdBuf.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(depthEffectsPipeline)
                encoder.setTexture(removedTex, index: 0)
                encoder.setTexture(depthTex,   index: 1)
                encoder.setTexture(dstTex,     index: 2)
                encoder.setBuffer(paramBuf, offset: 0, index: 0)
                encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
                encoder.endEncoding()
            }

            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            return uiImageFromTexture(dstTex, width: width, height: height)

        case .compress:
            // Single pass: painterly effects only
            guard let dstTex = device.makeTexture(descriptor: rgbaDesc) else { return nil }
            guard let cmdBuf = commandQueue.makeCommandBuffer() else { return nil }

            if let encoder = cmdBuf.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(depthEffectsPipeline)
                encoder.setTexture(srcTex,   index: 0)
                encoder.setTexture(depthTex, index: 1)
                encoder.setTexture(dstTex,   index: 2)
                encoder.setBuffer(paramBuf, offset: 0, index: 0)
                encoder.dispatchThreadgroups(grd, threadsPerThreadgroup: tgs)
                encoder.endEncoding()
            }

            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            return uiImageFromTexture(dstTex, width: width, height: height)
        }
    }

    private func backgroundModeRaw(_ mode: BackgroundMode) -> Int {
        switch mode {
        case .none:         return 0
        case .compress:     return 0
        case .blur:         return 1
        case .remove:       return 2
        }
    }

    func makeDepthTexture(from depthMap: UIImage) -> MTLTexture? {
        guard let cgImage = depthMap.cgImage else {
            return nil
        }
        return makeGrayscaleTexture(
            cgImage,
            width: cgImage.width,
            height: cgImage.height
        )
    }

    /// Create a single-channel (R8Unorm) texture from a grayscale CGImage,
    /// resizing if necessary to match the target dimensions.
    private func makeGrayscaleTexture(_ cgImage: CGImage, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        // Draw into single-channel buffer
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width
        )
        return texture
    }

    // MARK: - Texture helpers

    private func makeTextureFromCGImage(_ cgImage: CGImage) -> MTLTexture? {
        let width  = cgImage.width
        let height = cgImage.height

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        // Draw CGImage into a pixel buffer and upload
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        return texture
    }

    private func uiImageFromTexture(_ texture: MTLTexture, width: Int, height: Int) -> UIImage? {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        texture.getBytes(&pixels,
                         bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height),
                         mipmapLevel: 0)

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Swift-side param structs (must match Metal layout)

private struct GrayscaleParamsSwift {
    var pixelCount: UInt32
}

private struct RGBToOklabParamsSwift {
    var pixelCount: UInt32
}

private struct BandAssignParamsSwift {
    var pixelCount: UInt32
    var thresholdCount: UInt32
    var totalBands: UInt32
}

private struct ColorLabelParamsSwift {
    var pixelCount: UInt32
    var familyCount: UInt32
    var thresholdCount: UInt32
    var valuesPerFamily: UInt32
}

private struct ColorHistogramParamsSwift {
    var pixelCount: UInt32
    var lBins: UInt32
    var aBins: UInt32
    var bBins: UInt32
    var aMin: Float
    var aMax: Float
    var bMin: Float
    var bMax: Float
}

private struct QuantizeParamsSwift {
    var pixelCount: UInt32
    var thresholdCount: UInt32
    var totalLevels: UInt32
}

private struct KMeansAssignParamsSwift {
    var numPixels: UInt32
    var k: UInt32
    var lWeight: Float
}

private struct RemapParamsSwift {
    var pixelCount: UInt32
    var centroidCount: UInt32
}

private struct ValueRemapParamsSwift {
    var pixelCount: UInt32
    var totalLevels: UInt32
}

private struct KuwaharaParamsSwift {
    var width:  UInt32
    var height: UInt32
    var radius: Int32
}

private struct DepthEffectParamsSwift {
    var width: UInt32
    var height: UInt32
    var foregroundCutoff: Float
    var backgroundCutoff: Float
    var intensity: Float
    var backgroundMode: UInt32
}

// MARK: - Errors

enum MetalError: LocalizedError {
    case functionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .functionNotFound(let name): return "Metal function '\(name)' not found in shader library"
        }
    }
}
