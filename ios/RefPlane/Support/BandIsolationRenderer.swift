import UIKit

enum BandIsolationRenderer {
    /// Desaturates and darkens pixels that do not belong to the selected band,
    /// making the selected band's regions visually "pop" against a muted background.
    static func isolate(
        image: UIImage,
        pixelBands: [Int],
        selectedBand: Int,
        desaturation: Float = 0.85,
        dimming: Float = 0.45
    ) -> UIImage? {
        guard let (pixels, width, height) = image.toPixelData() else { return nil }
        let totalPixels = width * height
        guard pixelBands.count == totalPixels else { return nil }

        let keepColor = 1.0 - desaturation
        let brightness = 1.0 - dimming

        var output = pixels
        for index in 0..<totalPixels where pixelBands[index] != selectedBand {
            let base = index * 4
            let r = Float(output[base])
            let g = Float(output[base + 1])
            let b = Float(output[base + 2])
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            output[base]     = UInt8(min(255, max(0, (luma * desaturation + r * keepColor) * brightness)))
            output[base + 1] = UInt8(min(255, max(0, (luma * desaturation + g * keepColor) * brightness)))
            output[base + 2] = UInt8(min(255, max(0, (luma * desaturation + b * keepColor) * brightness)))
        }

        return UIImage.fromPixelData(output, width: width, height: height)
    }
}
