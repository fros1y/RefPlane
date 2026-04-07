import Foundation
import SwiftUI
import UIKit

struct PaletteBandSection: Equatable, Sendable {
    let band: Int
    let indices: [Int]
}

enum PaletteSections {
    static func makeSections(paletteBands: [Int], paletteCount: Int? = nil) -> [PaletteBandSection] {
        let upperBound = min(paletteBands.count, paletteCount ?? paletteBands.count)
        var grouped: [Int: [Int]] = [:]

        for index in 0..<upperBound {
            let band = paletteBands[index]
            guard band >= 0 else { continue }
            grouped[band, default: []].append(index)
        }

        return grouped.keys.sorted().map { band in
            PaletteBandSection(band: band, indices: grouped[band] ?? [])
        }
    }
}

enum PaletteColorNamer {
    static func name(for displayColor: Color) -> String? {
        let resolvedColor = UIColor(displayColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        let oklabColor = rgbToOklab(
            r: UInt8((red * 255).rounded()),
            g: UInt8((green * 255).rounded()),
            b: UInt8((blue * 255).rounded())
        )
        return name(for: oklabColor)
    }

    static func name(for oklabColor: OklabColor) -> String {
        let valueName = classifyValue(oklabColor.L)
        let chroma = sqrtf((oklabColor.a * oklabColor.a) + (oklabColor.b * oklabColor.b))
        let chromaName = classifyChroma(chroma)

        if chromaName == "Neutral" {
            return "\(valueName) Neutral"
        }

        let hueDegrees = normalizedHueDegrees(for: oklabColor)
        let hueName = classifyHue(hueDegrees)

        guard let temperatureName = classifyTemperature(hueDegrees, chroma: chroma) else {
            return "\(valueName) \(chromaName) \(hueName)"
        }

        return "\(valueName) \(temperatureName) \(chromaName) \(hueName)"
    }

    private static func classifyValue(_ lightness: Float) -> String {
        if lightness < 0.20 {
            return "Near-Black"
        }
        if lightness < 0.35 {
            return "Dark"
        }
        if lightness < 0.55 {
            return "Deep"
        }
        if lightness < 0.72 {
            return "Mid"
        }
        if lightness < 0.86 {
            return "Light"
        }
        return "Pale"
    }

    private static func classifyChroma(_ chroma: Float) -> String {
        if chroma < 0.03 {
            return "Neutral"
        }
        if chroma < 0.06 {
            return "Dull"
        }
        if chroma < 0.10 {
            return "Muted"
        }
        if chroma < 0.16 {
            return "Soft"
        }
        if chroma < 0.24 {
            return "Clear"
        }
        return "Bright"
    }

    private static func classifyHue(_ hueDegrees: Float) -> String {
        let hue = normalizedHueDegrees(hueDegrees)

        if hue >= 350 || hue < 20 {
            return "Red"
        }
        if hue < 45 {
            return "Orange"
        }
        if hue < 70 {
            return "Gold"
        }
        if hue < 95 {
            return "Yellow"
        }
        if hue < 140 {
            return "Green"
        }
        if hue < 185 {
            return "Teal"
        }
        if hue < 255 {
            return "Blue"
        }
        if hue < 315 {
            return "Violet"
        }
        return "Rose"
    }

    private static func classifyTemperature(_ hueDegrees: Float, chroma: Float) -> String? {
        let hue = normalizedHueDegrees(hueDegrees)

        if chroma < 0.05 {
            return nil
        }

        if hue >= 350 || hue < 20 {
            return (hue < 10 || hue >= 350) ? "Warm" : "Cool"
        }

        if hue < 70 {
            return "Warm"
        }

        if hue < 95 {
            return hue < 82.5 ? "Warm" : "Cool"
        }

        if hue < 140 {
            return hue < 117.5 ? "Warm" : "Cool"
        }

        if hue < 185 {
            return hue < 162.5 ? "Warm" : "Cool"
        }

        if hue < 255 {
            return hue < 220 ? "Cool" : "Warm"
        }

        if hue < 315 {
            return hue < 285 ? "Cool" : "Warm"
        }

        return hue < 332.5 ? "Cool" : "Warm"
    }

    private static func normalizedHueDegrees(for color: OklabColor) -> Float {
        normalizedHueDegrees(atan2f(color.b, color.a) * 180 / .pi)
    }

    private static func normalizedHueDegrees(_ hueDegrees: Float) -> Float {
        let normalized = hueDegrees.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}
