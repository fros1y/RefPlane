import UIKit
import SwiftUI

// MARK: - UIImage pixel data helpers

extension UIImage {

    /// NOTE: Do not call from the main/UI thread! Performs drawing and may block responsiveness.
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

    /// Async version of scaledDown that performs rendering off the main/UI thread.
    func scaledDownAsync(toMaxDimension maxDimension: CGFloat) async -> UIImage {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.scaledDown(toMaxDimension: maxDimension)
                continuation.resume(returning: result)
            }
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
    public func toPixelData() -> (data: [UInt8], width: Int, height: Int)? {
        // Normalize orientation first
        let normalised = normalizedOrientation()
        guard let cgImg = normalised.cgImage else { return nil }
        let width  = cgImg.width
        let height = cgImg.height
        let count  = width * height * 4
        var data   = [UInt8](repeating: 0, count: count)

        // Use noneSkipLast — photos are opaque so there's no alpha to
        // premultiply, which avoids the expensive premultiply-during-draw
        // plus the un-premultiply loop we'd need afterward.
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (data, width, height)
    }

    /// Build a UIImage from raw RGBA bytes.
    public static func fromPixelData(_ data: [UInt8], width: Int, height: Int) -> UIImage? {
        // Use CGDataProvider to avoid the two 30MB copies that the old
        // CGContext-based approach required (var copy + makeImage copy).
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        guard let cgImg = CGImage(
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
        ) else { return nil }
        return UIImage(cgImage: cgImg)
    }

    // Re-draw image at pixel resolution to normalize EXIF orientation.
    // Uses CGContext directly to avoid UIGraphicsImageRenderer's screen-scale
    // multiplication (which would create a 9× larger image on 3x devices).
    private func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        guard let cgImg = cgImage else { return self }
        let w = cgImg.width
        let h = cgImg.height
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return self }
        ctx.concatenate(orientationTransform(for: imageOrientation, width: w, height: h))
        let drawRect: CGRect
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            drawRect = CGRect(x: 0, y: 0, width: h, height: w)
        default:
            drawRect = CGRect(x: 0, y: 0, width: w, height: h)
        }
        ctx.draw(cgImg, in: drawRect)
        guard let result = ctx.makeImage() else { return self }
        return UIImage(cgImage: result)
    }

    private func orientationTransform(for orientation: UIImage.Orientation, width: Int, height: Int) -> CGAffineTransform {
        let w = CGFloat(width)
        let h = CGFloat(height)
        switch orientation {
        case .down, .downMirrored:
            return CGAffineTransform(translationX: w, y: h).rotated(by: .pi)
        case .left, .leftMirrored:
            return CGAffineTransform(translationX: w, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored:
            return CGAffineTransform(translationX: 0, y: h).rotated(by: -.pi / 2)
        default:
            return .identity
        }
    }
}
