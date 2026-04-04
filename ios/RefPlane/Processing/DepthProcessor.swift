import UIKit

// MARK: - Depth effect application coordinator

enum DepthProcessor {

    /// Apply depth-based painterly effects to the source image using the provided depth map.
    /// Uses Metal GPU path when available, falls back to simplified CPU processing.
    static func applyEffects(to image: UIImage, depthMap: UIImage, config: DepthConfig) -> UIImage? {
        guard let sourceCG = image.cgImage, let depthCG = depthMap.cgImage else { return nil }

        // GPU path
        if let ctx = MetalContext.shared {
            return ctx.applyDepthEffects(sourceCG, depthMap: depthCG, config: config)
        }

        // CPU fallback: simplified per-pixel contrast/saturation adjustment
        return cpuFallback(source: sourceCG, depth: depthCG, config: config)
    }

    static func thresholdPreview(
        depthMap: UIImage,
        backgroundCutoff: Double,
        cachedDepthTexture _: AnyObject? = nil
    ) -> UIImage? {
        guard let depthCG = depthMap.cgImage else { return nil }

        let width = depthCG.width
        let height = depthCG.height
        guard width > 0, height > 0 else { return nil }

        var depthPixels = [UInt8](repeating: 128, count: width * height)
        guard let context = CGContext(
            data: &depthPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(depthCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        let threshold = UInt8(max(0, min(255, Int((backgroundCutoff * 255).rounded()))))
        var output = [UInt8](repeating: 255, count: width * height * 4)

        for i in 0..<(width * height) {
            let pixel = depthPixels[i]
            let base = i * 4
            if pixel >= threshold {
                output[base] = 233
                output[base + 1] = 238
                output[base + 2] = 245
            } else {
                output[base] = pixel
                output[base + 1] = pixel
                output[base + 2] = pixel
            }
            output[base + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - CPU fallback

    private static func cpuFallback(source: CGImage, depth: CGImage, config: DepthConfig) -> UIImage? {
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        // Draw source into RGBA buffer
        var sourcePixels = [UInt8](repeating: 255, count: width * height * 4)
        guard let srcCtx = CGContext(
            data: &sourcePixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        srcCtx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Draw depth into grayscale buffer
        var depthPixels = [UInt8](repeating: 128, count: width * height)
        guard let depCtx = CGContext(
            data: &depthPixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        depCtx.draw(depth, in: CGRect(x: 0, y: 0, width: width, height: height))

        let fgCutoff = Float(config.foregroundCutoff)
        let bgCutoff = Float(config.backgroundCutoff)
        let intensity = Float(config.effectIntensity)
        let isRemove = config.backgroundMode == .remove

        var output = sourcePixels

        for i in 0..<(width * height) {
            let d = Float(depthPixels[i]) / 255.0
            let px = i * 4
            var r = Float(sourcePixels[px]) / 255.0
            var g = Float(sourcePixels[px + 1]) / 255.0
            var b = Float(sourcePixels[px + 2]) / 255.0

            // Background removal
            if isRemove && d > bgCutoff {
                let t = min((d - bgCutoff) / max(0.05, 1.0 - bgCutoff), 1.0)
                let blend = t * intensity
                r = r * (1 - blend) + blend
                g = g * (1 - blend) + blend
                b = b * (1 - blend) + blend
            }

            // Simple luminance
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

            if d < fgCutoff {
                // Foreground: boost contrast + warm shift
                let t = 1.0 - d / max(fgCutoff, 0.001)
                let strength = t * intensity * 0.3
                r = lum + (r - lum) * (1 + strength) + strength * 0.02
                g = lum + (g - lum) * (1 + strength)
                b = lum + (b - lum) * (1 + strength) - strength * 0.02
            } else if d > bgCutoff && !isRemove {
                // Background: reduce contrast + cool shift
                let t = min((d - bgCutoff) / max(0.05, 1.0 - bgCutoff), 1.0)
                let strength = t * intensity * 0.3
                r = lum + (r - lum) * (1 - strength) - strength * 0.02
                g = lum + (g - lum) * (1 - strength)
                b = lum + (b - lum) * (1 - strength) + strength * 0.03
            }

            output[px]     = UInt8(min(max(r * 255, 0), 255))
            output[px + 1] = UInt8(min(max(g * 255, 0), 255))
            output[px + 2] = UInt8(min(max(b * 255, 0), 255))
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
