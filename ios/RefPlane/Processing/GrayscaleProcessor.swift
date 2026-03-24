import UIKit

// MARK: - Grayscale conversion (Rec 709 linearized luminance)

enum GrayscaleProcessor {

    /// Convert image to grayscale using linearized Rec-709 weights.
    static func process(image: UIImage) -> UIImage? {
        guard let (pixels, width, height) = image.toPixelData() else { return nil }

        var out = [UInt8](repeating: 255, count: width * height * 4)

        for i in 0..<(width * height) {
            let base = i * 4
            let r = Float(pixels[base])     / 255.0
            let g = Float(pixels[base + 1]) / 255.0
            let b = Float(pixels[base + 2]) / 255.0
            let a = pixels[base + 3]

            // Linearize
            let rl = linearizeSRGB(r)
            let gl = linearizeSRGB(g)
            let bl = linearizeSRGB(b)

            // Luminance (Rec 709)
            let lum = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl

            // Gamma-encode back to display
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
