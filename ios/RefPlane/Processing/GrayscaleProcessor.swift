import UIKit

// MARK: - Grayscale conversion (Rec 709 linearized luminance)

enum GrayscaleProcessor {

    /// Convert image to grayscale using linearized Rec-709 weights.
    /// Uses Metal GPU compute when available, CPU fallback otherwise.
    static func process(image: UIImage) -> UIImage? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let (pixels, width, height) = image.toPixelData() else { return nil }
        let total = width * height
        let t1 = CFAbsoluteTimeGetCurrent()
        print("[Grayscale] toPixelData: \(String(format: "%.1f", (t1 - t0) * 1000)) ms")

        // GPU path
        if let gpu = MetalContext.shared,
           let out = gpu.processGrayscale(pixels: pixels, width: width, height: height) {
            let t2 = CFAbsoluteTimeGetCurrent()
            print("[Grayscale] ✅ GPU path — \(total) px in \(String(format: "%.1f", (t2 - t1) * 1000)) ms")
            let img = UIImage.fromPixelData(out, width: width, height: height)
            let t3 = CFAbsoluteTimeGetCurrent()
            print("[Grayscale] fromPixelData: \(String(format: "%.1f", (t3 - t2) * 1000)) ms")
            return img
        }

        // CPU fallback
        print("[Grayscale] ⚠️ CPU fallback (MetalContext.shared = \(MetalContext.shared == nil ? "nil" : "non-nil"))")
        let result = processCPU(pixels: pixels, width: width, height: height)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("[Grayscale] CPU — \(total) px in \(String(format: "%.1f", ms)) ms")
        return result
    }

    // MARK: - CPU fallback

    private static func processCPU(pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        var out = [UInt8](repeating: 255, count: width * height * 4)

        for i in 0..<(width * height) {
            let base = i * 4
            let r = Float(pixels[base])     / 255.0
            let g = Float(pixels[base + 1]) / 255.0
            let b = Float(pixels[base + 2]) / 255.0
            let a = pixels[base + 3]

            let rl = linearizeSRGB(r)
            let gl = linearizeSRGB(g)
            let bl = linearizeSRGB(b)

            let lum = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
            let encoded = delinearizeSRGB(Float(lum))
            let gray = UInt8(max(0, min(255, Int(encoded * 255 + 0.5))))

            out[base]     = gray
            out[base + 1] = gray
            out[base + 2] = gray
            out[base + 3] = a
        }

        return UIImage.fromPixelData(out, width: width, height: height)
    }
}
