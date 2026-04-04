import UIKit

// MARK: - Grayscale conversion

enum GrayscaleProcessor {

    /// Convert image to grayscale using the selected channel-combination method.
    /// Uses Metal GPU compute when available, CPU fallback otherwise.
    static func process(
        image: UIImage,
        conversion: GrayscaleConversion = .luminance
    ) -> UIImage? {
        guard conversion != .none else {
            return image
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        guard let (pixels, width, height) = image.toPixelData() else { return nil }
        let total = width * height
        let t1 = CFAbsoluteTimeGetCurrent()
        print("[Grayscale] toPixelData: \(String(format: "%.1f", (t1 - t0) * 1000)) ms")

        if conversion.usesGPUShortcut,
           let gpu = MetalContext.shared,
           let out = gpu.processGrayscale(pixels: pixels, width: width, height: height) {
            let t2 = CFAbsoluteTimeGetCurrent()
            print("[Grayscale] ✅ GPU path — \(total) px in \(String(format: "%.1f", (t2 - t1) * 1000)) ms")
            let img = UIImage.fromPixelData(out, width: width, height: height)
            let t3 = CFAbsoluteTimeGetCurrent()
            print("[Grayscale] fromPixelData: \(String(format: "%.1f", (t3 - t2) * 1000)) ms")
            return img
        }

        print("[Grayscale] ⚠️ CPU fallback (MetalContext.shared = \(MetalContext.shared == nil ? "nil" : "non-nil"))")
        let result = processCPU(
            pixels: pixels,
            width: width,
            height: height,
            conversion: conversion
        )
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("[Grayscale] CPU — \(total) px in \(String(format: "%.1f", ms)) ms")
        return result
    }

    static func grayscaleByte(r: Float, g: Float, b: Float, conversion: GrayscaleConversion) -> UInt8 {
        let rl = linearizeSRGB(r)
        let gl = linearizeSRGB(g)
        let bl = linearizeSRGB(b)

        let grayLinear: Float
        switch conversion {
        case .none, .luminance:
            grayLinear = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
        case .average:
            grayLinear = (rl + gl + bl) / 3.0
        case .lightness:
            grayLinear = (max(rl, gl, bl) + min(rl, gl, bl)) / 2.0
        }

        let encoded = delinearizeSRGB(grayLinear)
        return UInt8(max(0, min(255, Int(encoded * 255 + 0.5))))
    }

    private static func processCPU(
        pixels: [UInt8],
        width: Int,
        height: Int,
        conversion: GrayscaleConversion
    ) -> UIImage? {
        var out = [UInt8](repeating: 255, count: width * height * 4)

        for i in 0..<(width * height) {
            let base = i * 4
            let r = Float(pixels[base])     / 255.0
            let g = Float(pixels[base + 1]) / 255.0
            let b = Float(pixels[base + 2]) / 255.0
            let a = pixels[base + 3]

            let gray = grayscaleByte(r: r, g: g, b: b, conversion: conversion)

            out[base]     = gray
            out[base + 1] = gray
            out[base + 2] = gray
            out[base + 3] = a
        }

        return UIImage.fromPixelData(out, width: width, height: height)
    }
}
