import UIKit
import SwiftUI

// MARK: - Color Regions pipeline

enum ColorRegionsProcessor {

    struct Result {
        let image: UIImage
        /// Centroids in SwiftUI Color, grouped by band index
        let palette: [Color]
        let paletteBands: [Int]
    }

    static func process(image: UIImage, config: ColorConfig) -> Result? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let (pixels, width, height) = image.toPixelData() else { return nil }
        let total = width * height
        let t1 = CFAbsoluteTimeGetCurrent()
        print("[ColorRegions] toPixelData: \(String(format: "%.1f", (t1 - t0) * 1000)) ms")

        // GPU path
        if let gpu = MetalContext.shared {
            let result = processGPU(gpu: gpu, pixels: pixels, width: width, height: height, config: config)
            let t2 = CFAbsoluteTimeGetCurrent()
            print("[ColorRegions] ✅ GPU path — \(total) px, \(config.bands) bands × \(config.colorsPerBand) cpb in \(String(format: "%.1f", (t2 - t1) * 1000)) ms")
            return result
        }

        // CPU fallback
        print("[ColorRegions] ⚠️ CPU fallback (MetalContext.shared = nil)")
        let result = processCPU(pixels: pixels, width: width, height: height, config: config)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("[ColorRegions] CPU — \(total) px in \(String(format: "%.1f", ms)) ms")
        return result
    }

    // MARK: - GPU path

    private static func processGPU(
        gpu: MetalContext, pixels: [UInt8], width: Int, height: Int, config: ColorConfig
    ) -> Result? {
        let total = width * height
        let bands = max(2, min(6, config.bands))
        let cpb   = max(1, min(4, config.colorsPerBand))

        // 1. RGB → Oklab on GPU
        var stepStart = CFAbsoluteTimeGetCurrent()
        guard let (labArray, srcBuffer, labBuffer) = gpu.rgbToOklab(pixels: pixels, width: width, height: height) else {
            print("[ColorRegions] ⚠️ GPU rgb_to_oklab failed, falling back to CPU")
            return processCPU(pixels: pixels, width: width, height: height, config: config)
        }
        print("[ColorRegions]   rgb_to_oklab: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        // 2. Assign bands on GPU (reuse labBuffer)
        stepStart = CFAbsoluteTimeGetCurrent()
        let thresholdFloats = config.thresholds.map { Float($0) }
        guard let bandAssignRaw = gpu.assignBands(labBuffer: labBuffer, count: total,
                                                   thresholds: thresholdFloats,
                                                   totalBands: bands) else {
            print("[ColorRegions] ⚠️ GPU band_assign failed, falling back to CPU")
            return processCPU(pixels: pixels, width: width, height: height, config: config)
        }
        print("[ColorRegions]   band_assign: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        // 3. Build per-band pixel index lists (CPU — lightweight bookkeeping)
        var indicesByBand = Array(repeating: [Int](), count: bands)
        for i in 0..<total {
            indicesByBand[Int(bandAssignRaw[i])].append(i)
        }

        // 4. K-means per band (init + update on CPU, assignment on GPU)
        stepStart = CFAbsoluteTimeGetCurrent()
        var centroidsByBand: [[OklabColor]] = []
        var globalLabel = [Int32](repeating: 0, count: total)

        for bnd in 0..<bands {
            let indices = indicesByBand[bnd]
            let k = min(cpb, indices.count)

            if k < 1 || indices.isEmpty {
                let midL = bands > 1 ? Float(bnd) / Float(bands - 1) : 0.5
                centroidsByBand.append([OklabColor(L: midL, a: 0, b: 0)])
                continue
            }

            // Extract band pixel Lab data
            let bandLab = indices.map { OklabColor(L: labArray[$0 * 3], a: labArray[$0 * 3 + 1], b: labArray[$0 * 3 + 2]) }

            // K-means with GPU-accelerated assignment step
            let result = kmeansGPU(gpu: gpu, points: bandLab, k: k, lWeight: Float(0.1))

            var centroids = result.centroids

            // Apply warm/cool emphasis
            if config.warmCoolEmphasis != 0 {
                let angle = Float(config.warmCoolEmphasis) * Float.pi / 4
                centroids = centroids.map { c in
                    let r = sqrtf(c.a * c.a + c.b * c.b)
                    let theta = atan2f(c.b, c.a) + angle
                    return OklabColor(L: c.L, a: r * cosf(theta), b: r * sinf(theta))
                }
            }

            centroidsByBand.append(centroids)
            for (j, pi) in indices.enumerated() {
                let clusterIdx = result.assignments.isEmpty ? 0 : min(result.assignments[j], centroids.count - 1)
                globalLabel[pi] = Int32(bnd * cpb + clusterIdx)
            }
        }

        print("[ColorRegions]   kmeans (\(bands) bands): \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        // 5. Region cleanup (CPU — BFS)
        stepStart = CFAbsoluteTimeGetCurrent()
        if let factor = config.minRegionSize.factor {
            RegionCleaner.clean(labels: &globalLabel, width: width, height: height, minFactor: factor)
        }

        print("[ColorRegions]   region_cleanup: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        // 6. Build flat centroid table and remap on GPU
        stepStart = CFAbsoluteTimeGetCurrent()
        var flatCentroids: [Float] = []
        var palette: [Color] = []
        var paletteBands: [Int] = []

        for bnd in 0..<bands {
            for c in centroidsByBand[bnd] {
                flatCentroids.append(c.L)
                flatCentroids.append(c.a)
                flatCentroids.append(c.b)
                let (r, g, b) = oklabToRGB(c)
                palette.append(Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255))
                paletteBands.append(bnd)
            }
        }

        guard let out = gpu.remapByLabel(srcBuffer: srcBuffer, labels: globalLabel,
                                          centroids: flatCentroids, count: total) else {
            return nil
        }

        print("[ColorRegions]   remap_by_label: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        stepStart = CFAbsoluteTimeGetCurrent()
        guard let img = UIImage.fromPixelData(out, width: width, height: height) else { return nil }
        print("[ColorRegions]   fromPixelData: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")
        return Result(image: img, palette: palette, paletteBands: paletteBands)
    }

    // MARK: - GPU-accelerated k-means

    /// K-means with CPU centroid update + GPU assignment step.
    /// Uploads flat points once to a Metal buffer, reuses across iterations.
    private static func kmeansGPU(
        gpu: MetalContext, points: [OklabColor], k: Int, lWeight: Float
    ) -> KMeansResult {
        guard !points.isEmpty, k > 0 else {
            return KMeansResult(centroids: [], assignments: [])
        }
        let k = min(k, points.count)
        let n = points.count

        // Flatten to interleaved floats and upload once
        var flatPoints = [Float](repeating: 0, count: n * 3)
        flatPoints.withUnsafeMutableBufferPointer { buf in
            for i in 0..<n {
                buf[i * 3]     = points[i].L
                buf[i * 3 + 1] = points[i].a
                buf[i * 3 + 2] = points[i].b
            }
        }
        guard let pixLabBuffer = gpu.makeBuffer(flatPoints) else {
            return KMeansClusterer.cluster(points: points, k: k, lWeight: lWeight)
        }

        // K-means++ init on CPU (only k iterations, fast)
        var centroids = KMeansClusterer.kMeansPlusPlusInit(points: points, k: k, lWeight: lWeight)
        var assignments = [Int](repeating: 0, count: n)
        var iterations = 0

        for iter in 0..<20 {
            iterations = iter + 1
            // Assignment step on GPU (reuse pixLabBuffer)
            let flatCentroids = centroids.flatMap { [$0.L, $0.a, $0.b] }
            if let gpuAssign = gpu.kmeansAssign(pixelLabBuffer: pixLabBuffer, count: n,
                                                 centroidLab: flatCentroids, k: k, lWeight: lWeight) {
                var changed = false
                // Use withUnsafeBufferPointer to avoid bounds-check overhead
                gpuAssign.withUnsafeBufferPointer { assignBuf in
                    for i in 0..<n {
                        let newA = Int(assignBuf[i])
                        if assignments[i] != newA { changed = true; assignments[i] = newA }
                    }
                }
                if !changed { break }
            } else {
                print("[ColorRegions]   kmeansGPU: GPU assign failed on iter \(iter), falling back to CPU k-means")
                return KMeansClusterer.cluster(points: points, k: k, lWeight: lWeight)
            }

            // Update step on CPU (tiny: just k centroids)
            var sums = [(L: Float, a: Float, b: Float, count: Int)](
                repeating: (0, 0, 0, 0), count: centroids.count)
            for i in 0..<n {
                let c = assignments[i]
                sums[c].L += points[i].L
                sums[c].a += points[i].a
                sums[c].b += points[i].b
                sums[c].count += 1
            }

            var maxShift: Float = 0
            for c in 0..<centroids.count {
                if sums[c].count > 0 {
                    let n = Float(sums[c].count)
                    let newC = OklabColor(L: sums[c].L / n, a: sums[c].a / n, b: sums[c].b / n)
                    let shift = oklabDistance(centroids[c], newC)
                    if shift > maxShift { maxShift = shift }
                    centroids[c] = newC
                }
            }

            if maxShift < 0.001 { break }
        }

        print("[ColorRegions]   kmeansGPU: k=\(k), \(n) pts, \(iterations) iters (GPU)")
        return KMeansResult(centroids: centroids, assignments: assignments)
    }

    // MARK: - CPU fallback

    private static func processCPU(
        pixels: [UInt8], width: Int, height: Int, config: ColorConfig
    ) -> Result? {
        let total = width * height
        let bands = max(2, min(6, config.bands))
        let cpb   = max(1, min(4, config.colorsPerBand))

        // 1. Convert all pixels to Oklab
        var lab = [OklabColor](repeating: OklabColor(L: 0, a: 0, b: 0), count: total)
        for i in 0..<total {
            let base = i * 4
            lab[i] = rgbToOklab(r: pixels[base], g: pixels[base+1], b: pixels[base+2])
        }

        // 2. Assign each pixel to a brightness band
        let thresholds = config.thresholds.map { Float($0) }
        var bandAssign = [Int](repeating: 0, count: total)
        for i in 0..<total {
            var bnd = 0
            for t in thresholds { if lab[i].L >= t { bnd += 1 } }
            bandAssign[i] = min(bnd, bands - 1)
        }

        // 3. Build per-band index lists
        var indicesByBand = Array(repeating: [Int](), count: bands)
        for i in 0..<total {
            indicesByBand[bandAssign[i]].append(i)
        }

        var centroidsByBand: [[OklabColor]] = []
        var globalLabel = [Int32](repeating: 0, count: total)

        for bnd in 0..<bands {
            let indices = indicesByBand[bnd]
            let bandLab = indices.map { lab[$0] }
            let k = min(cpb, bandLab.count)

            var centroids: [OklabColor]
            var assignments: [Int]

            if k < 1 || bandLab.isEmpty {
                let midL = bands > 1 ? Float(bnd) / Float(bands - 1) : 0.5
                centroids = [OklabColor(L: midL, a: 0, b: 0)]
                assignments = []
            } else {
                let result = KMeansClusterer.cluster(points: bandLab, k: k, lWeight: 0.1)
                centroids = result.centroids
                assignments = result.assignments
            }

            if config.warmCoolEmphasis != 0 {
                let angle = Float(config.warmCoolEmphasis) * Float.pi / 4
                centroids = centroids.map { c in
                    let r = sqrtf(c.a * c.a + c.b * c.b)
                    let theta = atan2f(c.b, c.a) + angle
                    return OklabColor(L: c.L, a: r * cosf(theta), b: r * sinf(theta))
                }
            }

            centroidsByBand.append(centroids)
            for (j, pi) in indices.enumerated() {
                let clusterIdx = assignments.isEmpty ? 0 : min(assignments[j], centroids.count - 1)
                globalLabel[pi] = Int32(bnd * cpb + clusterIdx)
            }
        }

        // 4. Region cleanup
        if let factor = config.minRegionSize.factor {
            RegionCleaner.clean(labels: &globalLabel, width: width, height: height, minFactor: factor)
        }

        // 5. Build output
        var out = [UInt8](repeating: 255, count: total * 4)
        var palette: [Color] = []
        var paletteBands: [Int] = []

        var flatCentroids: [OklabColor] = []
        for bnd in 0..<bands {
            for c in centroidsByBand[bnd] {
                let (r, g, b) = oklabToRGB(c)
                palette.append(Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255))
                paletteBands.append(bnd)
                flatCentroids.append(c)
            }
        }

        for i in 0..<total {
            var lbl = Int(globalLabel[i])
            if lbl < 0 || lbl >= flatCentroids.count { lbl = 0 }
            let c = flatCentroids[lbl]
            let (r, g, b) = oklabToRGB(c)
            let base = i * 4
            out[base]     = r
            out[base + 1] = g
            out[base + 2] = b
            out[base + 3] = pixels[base + 3]
        }

        guard let img = UIImage.fromPixelData(out, width: width, height: height) else { return nil }
        return Result(image: img, palette: palette, paletteBands: paletteBands)
    }
}
