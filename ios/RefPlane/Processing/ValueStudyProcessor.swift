import UIKit

// MARK: - Value Study: grayscale → quantize into bands → optional cleanup

enum ValueStudyProcessor {

    struct Result {
        let image: UIImage
        /// Grayscale swatch for each level (0 = darkest)
        let levelColors: [UIColor]
    }

    static func process(image: UIImage, config: ValueConfig) -> Result? {
        guard let (pixels, width, height) = image.toPixelData() else { return nil }
        let levels = max(2, min(8, config.levels))
        let thresholds = config.thresholds  // values in 0-1, sorted ascending
        let total = width * height
        let start = CFAbsoluteTimeGetCurrent()

        // GPU path
        if let gpu = MetalContext.shared {
            let result = processGPU(gpu: gpu, pixels: pixels, width: width, height: height,
                              levels: levels, thresholds: thresholds, config: config)
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ValueStudy] ✅ GPU path — \(total) px, \(levels) levels in \(String(format: "%.1f", ms)) ms")
            return result
        }

        // CPU fallback
        print("[ValueStudy] ⚠️ CPU fallback (MetalContext.shared = nil)")
        let result = processCPU(pixels: pixels, width: width, height: height,
                          levels: levels, thresholds: thresholds, config: config)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("[ValueStudy] CPU — \(total) px in \(String(format: "%.1f", ms)) ms")
        return result
    }

    // MARK: - GPU path

    private static func processGPU(
        gpu: MetalContext, pixels: [UInt8], width: Int, height: Int,
        levels: Int, thresholds: [Double], config: ValueConfig
    ) -> Result? {
        let total = width * height
        let thresholdFloats = thresholds.map { Float($0) }

        // Quantize on GPU → get label map
        var stepStart = CFAbsoluteTimeGetCurrent()
        guard let (_, labelMap) = gpu.quantize(
            pixels: pixels, width: width, height: height,
            thresholds: thresholdFloats, totalLevels: levels
        ) else {
            print("[ValueStudy] ⚠️ GPU quantize failed, falling back to CPU")
            return processCPU(pixels: pixels, width: width, height: height,
                              levels: levels, thresholds: thresholds, config: config)
        }
        print("[ValueStudy]   quantize: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        var labels = labelMap

        // Region cleanup stays on CPU (BFS flood-fill with branching logic)
        stepStart = CFAbsoluteTimeGetCurrent()
        if let factor = config.minRegionSize.factor {
            RegionCleaner.clean(labels: &labels, width: width, height: height, minFactor: factor)
        }
        print("[ValueStudy]   region_cleanup: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        // Build level colors
        var levelColors: [UIColor] = []
        for lvl in 0..<levels {
            let t: UInt8
            if levels == 1 {
                t = 128
            } else {
                t = UInt8(Int(Float(lvl) / Float(levels - 1) * 255 + 0.5))
            }
            levelColors.append(UIColor(white: CGFloat(t) / 255.0, alpha: 1))
        }

        // Re-render labels → gray output on GPU
        stepStart = CFAbsoluteTimeGetCurrent()
        guard let out = gpu.valueRemap(pixels: pixels, labels: labels,
                                       count: total, totalLevels: levels) else {
            return nil
        }
        print("[ValueStudy]   value_remap: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stepStart) * 1000)) ms")

        guard let img = UIImage.fromPixelData(out, width: width, height: height) else { return nil }
        return Result(image: img, levelColors: levelColors)
    }

    // MARK: - CPU fallback

    private static func processCPU(
        pixels: [UInt8], width: Int, height: Int,
        levels: Int, thresholds: [Double], config: ValueConfig
    ) -> Result? {
        let total = width * height

        let thresholdBytes = thresholds.map { UInt8(max(0, min(255, Int($0 * 255)))) }

        var labelMap = [Int32](repeating: 0, count: total)

        for i in 0..<total {
            let base = i * 4
            let r = Float(pixels[base])     / 255.0
            let g = Float(pixels[base + 1]) / 255.0
            let b = Float(pixels[base + 2]) / 255.0

            let rl = linearizeSRGB(r)
            let gl = linearizeSRGB(g)
            let bl = linearizeSRGB(b)
            let lum = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
            let encoded = delinearizeSRGB(Float(lum))
            let gray = UInt8(max(0, min(255, Int(encoded * 255 + 0.5))))

            var level = 0
            for t in thresholdBytes { if gray >= t { level += 1 } }
            level = min(level, levels - 1)
            labelMap[i] = Int32(level)
        }

        if let factor = config.minRegionSize.factor {
            RegionCleaner.clean(labels: &labelMap, width: width, height: height, minFactor: factor)
        }

        var out = [UInt8](repeating: 255, count: total * 4)
        var levelColors: [UIColor] = []

        for lvl in 0..<levels {
            let t: UInt8
            if levels == 1 {
                t = 128
            } else {
                t = UInt8(Int(Float(lvl) / Float(levels - 1) * 255 + 0.5))
            }
            levelColors.append(UIColor(white: CGFloat(t) / 255.0, alpha: 1))
        }

        for i in 0..<total {
            let base = i * 4
            let level = Int(labelMap[i])
            let t: UInt8
            if levels == 1 {
                t = 128
            } else {
                t = UInt8(Int(Float(level) / Float(levels - 1) * 255 + 0.5))
            }
            out[base]     = t
            out[base + 1] = t
            out[base + 2] = t
            out[base + 3] = pixels[base + 3]
        }

        guard let img = UIImage.fromPixelData(out, width: width, height: height) else { return nil }
        return Result(image: img, levelColors: levelColors)
    }
}
