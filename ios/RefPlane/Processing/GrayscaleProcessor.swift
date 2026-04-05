import UIKit
import Accelerate

// MARK: - Grayscale conversion

enum GrayscaleProcessor {

    // Precomputed sRGB linearization LUT: byte value → linear float
    private static let srgbToLinear: [Float] = (0..<256).map {
        linearizeSRGB(Float($0) / 255.0)
    }

    // Precomputed sRGB delinearization LUT: quantized linear → byte
    private static let delinSteps = 4096
    private static let linearToSRGBByte: [UInt8] = (0...4096).map {
        let v = delinearizeSRGB(Float($0) / 4096.0)
        return UInt8(max(0, min(255, Int(v * 255 + 0.5))))
    }

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
        if conversion == .luminance,
           let result = processLuminanceVImage(pixels: pixels, width: width, height: height) {
            return result
        }
        return processWithLUT(pixels: pixels, width: width, height: height, conversion: conversion)
    }

    // MARK: - vImage luminance (color-managed sRGB → gray)

    private static func processLuminanceVImage(
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> UIImage? {
        let count = width * height

        guard let srcCS = CGColorSpace(name: CGColorSpace.sRGB),
              let srcFmt = vImage_CGImageFormat(
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  colorSpace: srcCS,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
              ),
              let grayFmt = vImage_CGImageFormat(
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  colorSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
              ),
              let converter = try? vImageConverter.make(
                  sourceFormat: srcFmt,
                  destinationFormat: grayFmt
              ) else {
            return nil
        }

        var grayPixels = [UInt8](repeating: 0, count: count)
        let alphaPixels = [UInt8](repeating: 255, count: count)
        var out = [UInt8](repeating: 0, count: count * 4)

        let ok: Bool = pixels.withUnsafeBufferPointer { srcPtr in
            grayPixels.withUnsafeMutableBufferPointer { grayPtr in
                var src = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: srcPtr.baseAddress!),
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * 4
                )
                var dst = vImage_Buffer(
                    data: grayPtr.baseAddress!,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width
                )
                return (try? converter.convert(source: src, destination: &dst)) != nil
            }
        }
        guard ok else { return nil }

        // Replicate gray → RGBA [gray, gray, gray, 255]
        grayPixels.withUnsafeBufferPointer { grayPtr in
            alphaPixels.withUnsafeBufferPointer { alphaPtr in
                out.withUnsafeMutableBufferPointer { outPtr in
                    var gBuf = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: grayPtr.baseAddress!),
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: width
                    )
                    var aBuf = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: alphaPtr.baseAddress!),
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: width
                    )
                    var oBuf = vImage_Buffer(
                        data: outPtr.baseAddress!,
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: width * 4
                    )
                    vImageConvert_Planar8toARGB8888(
                        &gBuf, &gBuf, &gBuf, &aBuf,
                        &oBuf, vImage_Flags(kvImageNoFlags)
                    )
                }
            }
        }

        return UIImage.fromPixelData(out, width: width, height: height)
    }

    // MARK: - LUT-accelerated path (average / lightness / luminance fallback)

    private static func processWithLUT(
        pixels: [UInt8],
        width: Int,
        height: Int,
        conversion: GrayscaleConversion
    ) -> UIImage? {
        let count = width * height
        var out = [UInt8](repeating: 255, count: count * 4)
        let linTable = srgbToLinear
        let delinTable = linearToSRGBByte
        let steps = delinSteps

        for i in 0..<count {
            let base = i * 4
            let rl = linTable[Int(pixels[base])]
            let gl = linTable[Int(pixels[base + 1])]
            let bl = linTable[Int(pixels[base + 2])]

            let grayLinear: Float
            switch conversion {
            case .none, .luminance:
                grayLinear = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
            case .average:
                grayLinear = (rl + gl + bl) / 3.0
            case .lightness:
                grayLinear = (max(rl, gl, bl) + min(rl, gl, bl)) / 2.0
            }

            let gray = delinTable[min(steps, Int(grayLinear * Float(steps) + 0.5))]
            out[base] = gray
            out[base + 1] = gray
            out[base + 2] = gray
            out[base + 3] = pixels[base + 3]
        }

        return UIImage.fromPixelData(out, width: width, height: height)
    }
}
