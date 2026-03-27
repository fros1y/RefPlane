import SwiftUI
import UIKit

enum GridLineTone: Equatable, Sendable {
    case black
    case white

    var color: Color {
        switch self {
        case .black:
            return .black
        case .white:
            return .white
        }
    }

    var luminance: Double {
        switch self {
        case .black:
            return 0
        case .white:
            return 1
        }
    }
}

enum GridLineColorResolver {
    static func resolvedColor(config: GridConfig, image: UIImage?) -> Color {
        switch config.lineStyle {
        case .black:
            return .black
        case .white:
            return .white
        case .custom:
            return config.customColor
        case .autoContrast:
            return autoContrastTone(forAverageLuminance: image?.averagePerceivedLuminance()).color
        }
    }

    static func autoContrastTone(forAverageLuminance averageLuminance: Double?) -> GridLineTone {
        guard let averageLuminance else { return .white }

        let blackContrast = contrastDistance(from: averageLuminance, to: .black)
        let whiteContrast = contrastDistance(from: averageLuminance, to: .white)
        return blackContrast >= whiteContrast ? .black : .white
    }

    static func contrastDistance(from backgroundLuminance: Double, to tone: GridLineTone) -> Double {
        abs(backgroundLuminance - tone.luminance)
    }
}

private extension UIImage {
    func averagePerceivedLuminance(maxSampleCount: Int = 4096) -> Double? {
        guard let (pixels, width, height) = toPixelData(), width > 0, height > 0 else { return nil }

        let sampleStep = max(1, Int(sqrt(Double(width * height) / Double(maxSampleCount))))
        var totalLuminance = 0.0
        var sampleCount = 0

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let base = (y * width + x) * 4
                let r = Float(pixels[base]) / 255.0
                let g = Float(pixels[base + 1]) / 255.0
                let b = Float(pixels[base + 2]) / 255.0

                let rl = linearizeSRGB(r)
                let gl = linearizeSRGB(g)
                let bl = linearizeSRGB(b)
                let luminance = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl

                totalLuminance += Double(luminance)
                sampleCount += 1
                x += sampleStep
            }
            y += sampleStep
        }

        guard sampleCount > 0 else { return nil }
        return totalLuminance / Double(sampleCount)
    }
}
