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
            print("[MetalContext] ✅ All 7 compute pipelines compiled successfully")
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
    let kmeansAssignPipeline: MTLComputePipelineState
    let quantizePipeline: MTLComputePipelineState
    let remapByLabelPipeline: MTLComputePipelineState
    let valueRemapPipeline: MTLComputePipelineState

    private init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let lib = device.makeDefaultLibrary() else { return nil }
        self.commandQueue = queue
        self.library = lib

        do {
            grayscalePipeline    = try Self.makePipeline(device: device, library: lib, name: "grayscale")
            rgbToOklabPipeline   = try Self.makePipeline(device: device, library: lib, name: "rgb_to_oklab")
            bandAssignPipeline   = try Self.makePipeline(device: device, library: lib, name: "band_assign")
            kmeansAssignPipeline = try Self.makePipeline(device: device, library: lib, name: "kmeans_assign")
            quantizePipeline     = try Self.makePipeline(device: device, library: lib, name: "quantize")
            remapByLabelPipeline = try Self.makePipeline(device: device, library: lib, name: "remap_by_label")
            valueRemapPipeline   = try Self.makePipeline(device: device, library: lib, name: "value_remap")
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
        return device.makeBuffer(bytes: data, length: MemoryLayout<T>.stride * data.count, options: .storageModeShared)
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

// MARK: - Errors

enum MetalError: LocalizedError {
    case functionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .functionNotFound(let name): return "Metal function '\(name)' not found in shader library"
        }
    }
}
