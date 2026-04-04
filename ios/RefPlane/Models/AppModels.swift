import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum RefPlaneMode: String, CaseIterable, Identifiable {
    case original, tonal, value, color
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Original"
        case .tonal:    return "Tonal"
        case .value:    return "Value"
        case .color:    return "Color"
        }
    }
    var iconName: String {
        switch self {
        case .original: return "photo"
        case .tonal:    return "circle.lefthalf.filled"
        case .value:    return "square.stack.3d.up"
        case .color:    return "paintpalette"
        }
    }
}

enum LineStyle: String, CaseIterable {
    case autoContrast = "Auto"
    case black        = "Black"
    case white        = "White"
    case custom       = "Custom"
}

enum MinRegionSize: String, CaseIterable {
    case off    = "Off"
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"

    var factor: Double? {
        switch self {
        case .off:    return nil
        case .small:  return 0.002
        case .medium: return 0.005
        case .large:  return 0.01
        }
    }
}

struct GridConfig {
    var enabled: Bool       = false
    var divisions: Int      = 4
    var showDiagonals: Bool    = false
    var lineStyle: LineStyle   = .autoContrast
    var customColor: Color     = .white
    var opacity: Double        = 0.7
}

// MARK: - Value threshold distribution

enum ThresholdDistribution: String, CaseIterable, Identifiable {
    case even     = "Even"
    case shadows  = "Shadow Detail"
    case lights   = "Light Detail"
    case custom   = "Custom"

    var id: String { rawValue }

    /// Compute thresholds for the given number of levels using this distribution.
    func thresholds(for levels: Int) -> [Double] {
        switch self {
        case .even:
            return QuantizationBias.thresholds(for: levels, bias: 0)
        case .shadows:
            return QuantizationBias.thresholds(for: levels, bias: 1)
        case .lights:
            return QuantizationBias.thresholds(for: levels, bias: -1)
        case .custom:
            // Custom returns even as a starting point; user adjusts manually.
            return QuantizationBias.thresholds(for: levels, bias: 0)
        }
    }
}

enum GrayscaleConversion: String, CaseIterable, Identifiable {
    case none = "None"
    case luminance = "Luminance"
    case average = "Average"
    case lightness = "Lightness"

    var id: String { rawValue }

    var usesGPUShortcut: Bool {
        self == .luminance
    }
}

struct ValueConfig {
    var grayscaleConversion: GrayscaleConversion = .none
    var levels: Int                        = 3
    var thresholds: [Double]               = defaultThresholds(for: 3)
    var distribution: ThresholdDistribution = .even
    var quantizationBias: Double = 0
}

// MARK: - Pigment palette presets

enum PigmentPreset: String, CaseIterable, Identifiable {
    case all      = "All"
    case zorn     = "Zorn"
    case primary  = "Primary"
    case warm     = "Warm"
    case cool     = "Cool"

    var id: String { rawValue }

    /// The pigment IDs belonging to this preset.
    var pigmentIDs: Set<String> {
        switch self {
        case .all:
            return Set(SpectralDataStore.essentialPigments.map(\.id))
        case .zorn:
            // Anders Zorn palette: Yellow Ochre, Cad Red Medium, Carbon Black + Titanium White
            return ["yellow_ochre", "cad_red_medium", "carbon_black", "titanium_white"]
        case .primary:
            // Split-primary: warm/cool of each primary + white + black
            return [
                "cad_red_medium", "quin_crimson",
                "cad_yellow_medium", "cadmium_yellow_light",
                "ultramarine_blue", "phthalo_blue_gs",
                "carbon_black", "titanium_white"
            ]
        case .warm:
            return [
                "cad_red_medium", "cad_red_dark", "cadmium_orange",
                "cad_yellow_medium", "yellow_ochre", "raw_sienna",
                "burnt_sienna", "burnt_umber", "titanium_white", "carbon_black"
            ]
        case .cool:
            return [
                "ultramarine_blue", "phthalo_blue_gs", "cerulean_blue_chromium",
                "phthalo_green_bs", "chromium_oxide", "dioxazine_purple",
                "paynes_gray", "raw_umber", "titanium_white", "carbon_black"
            ]
        }
    }
}

struct ColorConfig {
    var paletteSelectionEnabled: Bool = false
    var numShades: Int         = 24
    var enabledPigmentIDs: Set<String> = {
        ColorConfig.loadEnabledPigmentIDs()
            ?? Set(SpectralDataStore.essentialPigments.map(\.id))
    }()
    var paletteSpread: Double  = 0
    var quantizationBias: Double = 0
    var maxPigmentsPerMix: Int = 3
    var minConcentration: Float = 0.02

    // MARK: - Persistence

    private static let enabledKey = "ColorConfig.enabledPigmentIDs"
    private static let customKey  = "ColorConfig.customPigmentIDs"

    /// Persist the current pigment selection.
    func saveEnabledPigmentIDs() {
        let array = Array(enabledPigmentIDs).sorted()
        UserDefaults.standard.set(array, forKey: ColorConfig.enabledKey)
    }

    /// Save the current selection as the "custom" palette (separate from preset).
    func saveCustomPigmentIDs() {
        let array = Array(enabledPigmentIDs).sorted()
        UserDefaults.standard.set(array, forKey: ColorConfig.customKey)
    }

    /// Load persisted pigment selection, or nil if none saved.
    static func loadEnabledPigmentIDs() -> Set<String>? {
        guard let array = UserDefaults.standard.stringArray(forKey: enabledKey) else { return nil }
        let valid = Set(array).intersection(Set(SpectralDataStore.essentialPigments.map(\.id)))
        return valid.isEmpty ? nil : valid
    }

    /// Load the saved custom palette, falling back to all essentials.
    static func loadCustomPigmentIDs() -> Set<String> {
        guard let array = UserDefaults.standard.stringArray(forKey: customKey) else {
            return Set(SpectralDataStore.essentialPigments.map(\.id))
        }
        let valid = Set(array).intersection(Set(SpectralDataStore.essentialPigments.map(\.id)))
        return valid.isEmpty ? Set(SpectralDataStore.essentialPigments.map(\.id)) : valid
    }
}

enum QuantizationBias {
    static let range: ClosedRange<Double> = -1...1
    static let step: Double = 0.01

    private static let maxExponent: Double = 5.0 / 3.0

    static func displayName(for bias: Double) -> String {
        let clampedBias = clamped(bias)
        if abs(clampedBias) < 0.04 {
            return "Even"
        }

        return clampedBias < 0
            ? "Light Detail"
            : "Shadow Detail"
    }

    static func luminanceExponent(for bias: Double) -> Float {
        Float(pow(maxExponent, -clamped(bias)))
    }

    static func thresholds(for levels: Int, bias: Double) -> [Double] {
        guard levels > 1 else { return [] }
        let exponent = pow(maxExponent, clamped(bias))
        return (1..<levels).map { index in
            pow(Double(index) / Double(levels), exponent)
        }
    }

    static func distribution(for bias: Double) -> ThresholdDistribution {
        let clampedBias = clamped(bias)
        if abs(clampedBias) < 0.04 {
            return .even
        }
        return clampedBias < 0 ? .lights : .shadows
    }

    static func clamped(_ bias: Double) -> Double {
        min(max(bias, range.lowerBound), range.upperBound)
    }
}

func defaultThresholds(for levels: Int) -> [Double] {
    guard levels > 1 else { return [] }
    return (1..<levels).map { Double($0) / Double(levels) }
}

// MARK: - Abstraction method model

enum AbstractionProcessingKind {
    case superResolution4x
    case fullImageModel
    case metalShader
}

enum AbstractionMethod: String, CaseIterable, Identifiable {
    case apisr = "APISR"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apisr:
            return "Balanced"
        }
    }

    var processingKind: AbstractionProcessingKind {
        return .superResolution4x
    }

    var modelBundleName: String? {
        return "APISR_GRL_x4"
    }
}

// MARK: - Depth-based painterly effects

enum BackgroundMode: String, CaseIterable, Identifiable {
    case none = "No"
    case compress = "Compress"
    case blur = "Blur"
    case remove = "Remove"
    var id: String { rawValue }
}

struct DepthConfig {
    var enabled: Bool = false
    var foregroundCutoff: Double = 0.33
    var backgroundCutoff: Double = 0.66
    var effectIntensity: Double = 0.5     // global intensity multiplier
    var backgroundMode: BackgroundMode = .none
}

struct ContourConfig {
    var enabled: Bool        = false
    var levels: Int          = 5          // number of isoline levels (2–64)
    var lineStyle: LineStyle = .autoContrast
    var customColor: Color   = .white
    var opacity: Double      = 0.7
}

// MARK: - Image import/export payloads

struct SourceImageMetadata {
    var properties: [String: Any] = [:]
    var uniformTypeIdentifier: String? = nil

    static let empty = SourceImageMetadata()
}

struct ImportedImagePayload {
    var image: UIImage
    var metadata: SourceImageMetadata

    init(image: UIImage, metadata: SourceImageMetadata = .empty) {
        self.image = image
        self.metadata = metadata
    }
}

struct ExportedImagePayload {
    var imageData: Data
    var contentType: UTType
}
