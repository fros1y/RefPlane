import SwiftUI

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

struct ValueConfig {
    var levels: Int              = 3
    var thresholds: [Double]     = defaultThresholds(for: 3)
}

struct ColorConfig {
    var numShades: Int         = 8
    var numTubes: Int          = 6
    var paletteSpread: Double  = 0
    var maxPigmentsPerMix: Int = 3
    var minConcentration: Float = 0.02
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
