import UIKit
import SwiftUI

// MARK: - UIImage pixel data helpers

extension UIImage {

    /// Scale image down so longest dimension ≤ maxDimension, maintaining aspect ratio.
    func scaledDown(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let maxWH = max(size.width, size.height)
        guard maxWH > maxDimension else { return self }
        let scale = maxDimension / maxWH
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Crop using a normalized rect (0..1 in both axes relative to image size).
    func cropped(to normalizedRect: CGRect) -> UIImage {
        let pixelRect = CGRect(
            x: normalizedRect.origin.x * size.width,
            y: normalizedRect.origin.y * size.height,
            width: normalizedRect.size.width * size.width,
            height: normalizedRect.size.height * size.height
        )
        guard let cgImg = cgImage?.cropping(to: pixelRect
            .applying(CGAffineTransform(scaleX: scale, y: scale))) else { return self }
        return UIImage(cgImage: cgImg, scale: scale, orientation: imageOrientation)
    }

    /// Decode image to raw RGBA bytes. Returns nil on failure.
    func toPixelData() -> (data: [UInt8], width: Int, height: Int)? {
        // Normalize orientation first
        let normalised = normalizedOrientation()
        guard let cgImg = normalised.cgImage else { return nil }
        let width  = cgImg.width
        let height = cgImg.height
        let count  = width * height * 4
        var data   = [UInt8](repeating: 0, count: count)

        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Un-premultiply alpha
        for i in 0..<(width * height) {
            let base = i * 4
            let a = data[base + 3]
            if a > 0 && a < 255 {
                let af = Float(a) / 255.0
                data[base]     = UInt8(min(255, Int(Float(data[base])     / af + 0.5)))
                data[base + 1] = UInt8(min(255, Int(Float(data[base + 1]) / af + 0.5)))
                data[base + 2] = UInt8(min(255, Int(Float(data[base + 2]) / af + 0.5)))
            }
        }

        return (data, width, height)
    }

    /// Build a UIImage from raw RGBA bytes.
    static func fromPixelData(_ data: [UInt8], width: Int, height: Int) -> UIImage? {
        var mutableData = data
        guard let ctx = CGContext(
            data: &mutableData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        guard let cgImg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cgImg)
    }

    // Re-draw image to normalize orientation
    private func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(at: .zero) }
    }
}
