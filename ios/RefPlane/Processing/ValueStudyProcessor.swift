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
        let total = width * height
        let levels = max(2, min(8, config.levels))
        let thresholds = config.thresholds  // values in 0-1, sorted ascending

        // Build threshold table (in 0-255 linear luminance space)
        // Thresholds are in perceptual (display-encoded) space
        let thresholdBytes = thresholds.map { UInt8(max(0, min(255, Int($0 * 255)))) }

        // Assign each pixel to a level
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

        // Optional region cleanup
        if let factor = config.minRegionSize.factor {
            RegionCleaner.clean(labels: &labelMap, width: width, height: height, minFactor: factor)
        }

        // Map levels to evenly-spaced grayscale (0 = black, levels-1 = white)
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
