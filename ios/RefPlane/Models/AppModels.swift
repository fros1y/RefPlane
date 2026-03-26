import SwiftUI

enum RefPlaneMode: String, CaseIterable, Identifiable {
    case original, tonal, value, color
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Source"
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

enum CellAspect: String, CaseIterable {
    case square     = "Square"
    case matchImage = "Image"
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
    var cellAspect: CellAspect = .square
    var showDiagonals: Bool    = false
    var showCenterLines: Bool  = false
    var lineStyle: LineStyle   = .autoContrast
    var customColor: Color     = .white
    var opacity: Double        = 0.7
}

struct ValueConfig {
    var levels: Int              = 3
    var thresholds: [Double]     = defaultThresholds(for: 3)
    var minRegionSize: MinRegionSize = .small
}

struct ColorConfig {
    var bands: Int               = 3
    var colorsPerBand: Int       = 2
    var warmCoolEmphasis: Double = 0
    var thresholds: [Double]     = defaultThresholds(for: 3)
    var minRegionSize: MinRegionSize = .small
}

func defaultThresholds(for levels: Int) -> [Double] {
    guard levels > 1 else { return [] }
    return (1..<levels).map { Double($0) / Double(levels) }
}

// MARK: - Simplification method model

enum SimplificationProcessingKind {
    case superResolution4x
    case fullImageModel
    case metalShader
}

enum SimplificationMethod: String, CaseIterable, Identifiable {
    case apisr = "APISR"

    var id: String { rawValue }
    var label: String { rawValue }

    var processingKind: SimplificationProcessingKind {
        return .superResolution4x
    }

    var modelBundleName: String? {
        return "APISR_GRL_x4"
    }
}
