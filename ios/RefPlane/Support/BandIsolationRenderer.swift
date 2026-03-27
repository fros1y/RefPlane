import UIKit

enum BandIsolationRenderer {
    static func isolate(
        image: UIImage,
        pixelBands: [Int],
        selectedBand: Int,
        nonSelectedColor: UInt8 = 255
    ) -> UIImage? {
        guard let (pixels, width, height) = image.toPixelData() else { return nil }
        let totalPixels = width * height
        guard pixelBands.count == totalPixels else { return nil }

        var output = pixels
        for index in 0..<totalPixels where pixelBands[index] != selectedBand {
            let base = index * 4
            output[base] = nonSelectedColor
            output[base + 1] = nonSelectedColor
            output[base + 2] = nonSelectedColor
        }

        return UIImage.fromPixelData(output, width: width, height: height)
    }
}
