import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum RefPlaneMode: String, CaseIterable, Identifiable, Codable {
    case original, tonal, value, color
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Natural"
        case .tonal:    return "Tonal"
        case .value:    return "Value"
        case .color:    return "Paletted"
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

enum LineStyle: String, CaseIterable, Codable {
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

enum ThresholdDistribution: String, CaseIterable, Identifiable, Codable {
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

enum GrayscaleConversion: String, CaseIterable, Identifiable, Codable {
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
    var paletteSpread: Double  = 1
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
}

enum AbstractionMethod: String, CaseIterable, Identifiable, Codable {
    case apisr = "APISR"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .apisr
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

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

enum BackgroundMode: String, CaseIterable, Identifiable, Codable {
    case none = "Off"
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

enum DepthSource {
    case embedded
    case estimated
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
    var embeddedDepthMap: UIImage?

    init(
        image: UIImage,
        metadata: SourceImageMetadata = .empty,
        embeddedDepthMap: UIImage? = nil
    ) {
        self.image = image
        self.metadata = metadata
        self.embeddedDepthMap = embeddedDepthMap
    }
}

struct ExportedImagePayload {
    var image: UIImage
    var imageData: Data
    var contentType: UTType
}
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Enums & Errors

enum TransformPresetSelection: Hashable {
    case previous
    case appDefault
    case saved(UUID)
}

enum TransformPresetError: LocalizedError {
    case emptyName
    case duplicateName
    case presetNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Preset name cannot be empty."
        case .duplicateName:
            return "A preset with that name already exists."
        case .presetNotFound:
            return "Preset not found."
        }
    }
}

// MARK: - Legacy / Required Codable Structs

struct SavedTransformPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var snapshot: TransformationSnapshot
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: Color) {
        let uiColor = UIColor(color)
        var redComponent: CGFloat = 0
        var greenComponent: CGFloat = 0
        var blueComponent: CGFloat = 0
        var alphaComponent: CGFloat = 0

        if uiColor.getRed(
            &redComponent,
            green: &greenComponent,
            blue: &blueComponent,
            alpha: &alphaComponent
        ) {
            red = redComponent
            green = greenComponent
            blue = blueComponent
            alpha = alphaComponent
        } else {
            red = 1
            green = 1
            blue = 1
            alpha = 1
        }
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct TransformationSnapshot: Codable, Equatable {
    var activeMode: RefPlaneMode
    var abstractionStrength: Double
    var abstractionMethod: AbstractionMethod

    var gridEnabled: Bool
    var gridDivisions: Int
    var gridShowDiagonals: Bool
    var gridLineStyle: LineStyle
    var gridCustomColor: CodableColor
    var gridOpacity: Double

    var grayscaleConversion: GrayscaleConversion
    var valueLevels: Int
    var valueThresholds: [Double]
    var valueDistribution: ThresholdDistribution
    var valueQuantizationBias: Double

    var paletteSelectionEnabled: Bool
    var colorLimit: Int
    var enabledPigmentIDs: [String]
    var paletteSpread: Double
    var colorQuantizationBias: Double
    var maxPigmentsPerMix: Int
    var minConcentration: Float

    var depthEnabled: Bool
    var foregroundCutoff: Double
    var backgroundCutoff: Double
    var depthEffectIntensity: Double
    var backgroundMode: BackgroundMode

    var contourEnabled: Bool
    var contourLevels: Int
    var contourLineStyle: LineStyle
    var contourCustomColor: CodableColor
    var contourOpacity: Double

    // Explicit memberwise init (required because custom init(from:) suppresses synthesis).
    init(
        activeMode: RefPlaneMode,
        abstractionStrength: Double,
        abstractionMethod: AbstractionMethod,
        gridEnabled: Bool,
        gridDivisions: Int,
        gridShowDiagonals: Bool,
        gridLineStyle: LineStyle,
        gridCustomColor: CodableColor,
        gridOpacity: Double,
        grayscaleConversion: GrayscaleConversion,
        valueLevels: Int,
        valueThresholds: [Double],
        valueDistribution: ThresholdDistribution,
        valueQuantizationBias: Double,
        paletteSelectionEnabled: Bool,
        colorLimit: Int,
        enabledPigmentIDs: [String],
        paletteSpread: Double,
        colorQuantizationBias: Double,
        maxPigmentsPerMix: Int,
        minConcentration: Float,
        depthEnabled: Bool,
        foregroundCutoff: Double,
        backgroundCutoff: Double,
        depthEffectIntensity: Double,
        backgroundMode: BackgroundMode,
        contourEnabled: Bool,
        contourLevels: Int,
        contourLineStyle: LineStyle,
        contourCustomColor: CodableColor,
        contourOpacity: Double
    ) {
        self.activeMode = activeMode
        self.abstractionStrength = abstractionStrength
        self.abstractionMethod = abstractionMethod
        self.gridEnabled = gridEnabled
        self.gridDivisions = gridDivisions
        self.gridShowDiagonals = gridShowDiagonals
        self.gridLineStyle = gridLineStyle
        self.gridCustomColor = gridCustomColor
        self.gridOpacity = gridOpacity
        self.grayscaleConversion = grayscaleConversion
        self.valueLevels = valueLevels
        self.valueThresholds = valueThresholds
        self.valueDistribution = valueDistribution
        self.valueQuantizationBias = valueQuantizationBias
        self.paletteSelectionEnabled = paletteSelectionEnabled
        self.colorLimit = colorLimit
        self.enabledPigmentIDs = enabledPigmentIDs
        self.paletteSpread = paletteSpread
        self.colorQuantizationBias = colorQuantizationBias
        self.maxPigmentsPerMix = maxPigmentsPerMix
        self.minConcentration = minConcentration
        self.depthEnabled = depthEnabled
        self.foregroundCutoff = foregroundCutoff
        self.backgroundCutoff = backgroundCutoff
        self.depthEffectIntensity = depthEffectIntensity
        self.backgroundMode = backgroundMode
        self.contourEnabled = contourEnabled
        self.contourLevels = contourLevels
        self.contourLineStyle = contourLineStyle
        self.contourCustomColor = contourCustomColor
        self.contourOpacity = contourOpacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeMode = try c.decode(RefPlaneMode.self, forKey: .activeMode)
        abstractionStrength = try c.decode(Double.self, forKey: .abstractionStrength)
        abstractionMethod = try c.decode(AbstractionMethod.self, forKey: .abstractionMethod)
        gridEnabled = try c.decode(Bool.self, forKey: .gridEnabled)
        gridDivisions = try c.decode(Int.self, forKey: .gridDivisions)
        gridShowDiagonals = try c.decode(Bool.self, forKey: .gridShowDiagonals)
        gridLineStyle = try c.decode(LineStyle.self, forKey: .gridLineStyle)
        gridCustomColor = try c.decode(CodableColor.self, forKey: .gridCustomColor)
        gridOpacity = try c.decode(Double.self, forKey: .gridOpacity)
        grayscaleConversion = try c.decode(GrayscaleConversion.self, forKey: .grayscaleConversion)
        valueLevels = try c.decode(Int.self, forKey: .valueLevels)
        valueThresholds = try c.decode([Double].self, forKey: .valueThresholds)
        valueDistribution = try c.decode(ThresholdDistribution.self, forKey: .valueDistribution)
        valueQuantizationBias = try c.decode(Double.self, forKey: .valueQuantizationBias)
        
        paletteSelectionEnabled = try c.decode(Bool.self, forKey: .paletteSelectionEnabled)
        colorLimit = try c.decode(Int.self, forKey: .colorLimit)
        
        enabledPigmentIDs = try c.decode([String].self, forKey: .enabledPigmentIDs)
        
        paletteSpread = try c.decode(Double.self, forKey: .paletteSpread)
        colorQuantizationBias = try c.decode(Double.self, forKey: .colorQuantizationBias)
        maxPigmentsPerMix = try c.decode(Int.self, forKey: .maxPigmentsPerMix)
        minConcentration = try c.decode(Float.self, forKey: .minConcentration)
        
        depthEnabled = try c.decode(Bool.self, forKey: .depthEnabled)
        foregroundCutoff = try c.decode(Double.self, forKey: .foregroundCutoff)
        backgroundCutoff = try c.decode(Double.self, forKey: .backgroundCutoff)
        depthEffectIntensity = try c.decode(Double.self, forKey: .depthEffectIntensity)
        backgroundMode = try c.decode(BackgroundMode.self, forKey: .backgroundMode)
        contourEnabled = try c.decode(Bool.self, forKey: .contourEnabled)
        contourLevels = try c.decode(Int.self, forKey: .contourLevels)
        contourLineStyle = try c.decode(LineStyle.self, forKey: .contourLineStyle)
        contourCustomColor = try c.decode(CodableColor.self, forKey: .contourCustomColor)
        contourOpacity = try c.decode(Double.self, forKey: .contourOpacity)
    }
}

struct TransformPresetStore: Codable {
    var schemaVersion: Int
    var savedPresets: [SavedTransformPreset]
    var previousSnapshot: TransformationSnapshot?
}

// MARK: - Manager

@Observable @MainActor
class TransformPresetManager {
    static let storeKey = "AppState.transformPresetStore.v1"
    
    var savedPresets: [SavedTransformPreset] = []
    var previousSnapshot: TransformationSnapshot?
    
    init() {
        loadStore()
    }
    
    func savePreset(named rawName: String, snapshot: TransformationSnapshot) throws -> UUID {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw TransformPresetError.emptyName
        }

        let normalizedName = normalizedPresetName(name)
        guard !savedPresets.contains(where: { normalizedPresetName($0.name) == normalizedName }) else {
            throw TransformPresetError.duplicateName
        }

        let now = Date()
        let preset = SavedTransformPreset(
            id: UUID(),
            name: name,
            createdAt: now,
            updatedAt: now,
            snapshot: snapshot
        )

        savedPresets.append(preset)
        savedPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistStore()
        return preset.id
    }

    func renamePreset(id: UUID, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw TransformPresetError.emptyName
        }

        let normalizedName = normalizedPresetName(name)
        guard !savedPresets.contains(where: {
            $0.id != id && normalizedPresetName($0.name) == normalizedName
        }) else {
            throw TransformPresetError.duplicateName
        }

        guard let index = savedPresets.firstIndex(where: { $0.id == id }) else {
            throw TransformPresetError.presetNotFound
        }

        savedPresets[index].name = name
        savedPresets[index].updatedAt = Date()
        savedPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistStore()
    }

    func deletePreset(id: UUID) {
        savedPresets.removeAll { $0.id == id }
        persistStore()
    }
    
    func savePreviousSnapshot(_ snapshot: TransformationSnapshot) {
        self.previousSnapshot = snapshot
        persistStore()
    }

    func normalizedPresetName(_ name: String) -> String {
        return name.lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func loadStore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            let store = try decoder.decode(TransformPresetStore.self, from: data)
            if store.schemaVersion == 1 {
                savedPresets = store.savedPresets
                savedPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                previousSnapshot = store.previousSnapshot
            }
        } catch {
            print("Failed to decode transform presets: \(error)")
        }
    }

    func persistStore() {
        let store = TransformPresetStore(
            schemaVersion: 1,
            savedPresets: savedPresets,
            previousSnapshot: previousSnapshot
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(store)
            UserDefaults.standard.set(encoded, forKey: Self.storeKey)
        } catch {
            print("Failed to encode transform presets: \(error)")
        }
    }
}

// MARK: - AppState child state

@Observable
@MainActor
final class TransformState {
    var activeMode: RefPlaneMode = .original
    var gridConfig: GridConfig = GridConfig()
    var valueConfig: ValueConfig = ValueConfig()
    var colorConfig: ColorConfig = ColorConfig()
    var contourConfig: ContourConfig = ContourConfig()

    var abstractionStrength: Double = 0.5
    var abstractionMethod: AbstractionMethod = .apisr

    var previousTransformSnapshot: TransformationSnapshot? = nil
    var selectedTransformPresetSelection: TransformPresetSelection = .previous
    var presetManager: TransformPresetManager = TransformPresetManager()

    var savedTransformPresets: [SavedTransformPreset] {
        presetManager.savedPresets
    }

    var abstractionIsEnabled: Bool {
        abstractionStrength > 0
    }

    var availableAbstractionMethods: [AbstractionMethod] {
        AbstractionMethod.allCases.filter { method in
            switch method.processingKind {
            case .superResolution4x, .fullImageModel:
                guard let name = method.modelBundleName else { return false }
                return Bundle.main.url(forResource: name, withExtension: "mlmodelc") != nil
                    || Bundle.main.url(forResource: name, withExtension: "mlpackage") != nil
                    || Bundle.main.url(forResource: name, withExtension: "mlmodel") != nil
            }
        }
    }
}

@Observable
@MainActor
final class DepthState {
    var depthConfig: DepthConfig = DepthConfig()
    var depthMap: UIImage? = nil
    var embeddedDepthMap: UIImage? = nil
    var depthSource: DepthSource? = nil
    var depthProcessedImage: UIImage? = nil
    var depthRange: ClosedRange<Double> = 0...1

    var isEditingDepthThreshold: Bool = false
    var depthThresholdPreview: UIImage? = nil
    var contourSegments: [GridLineSegment] = []

    @ObservationIgnored var cachedDepthTexture: AnyObject? = nil
    @ObservationIgnored var cachedSourceTexture: AnyObject? = nil
    @ObservationIgnored var depthSliderActive: Bool = false
}

@Observable
@MainActor
final class PipelineState {
    var isProcessing: Bool = false
    var isSimplifying: Bool = false
    var processingProgress: Double = 0
    var processingLabel: String = "Processing…"
    var processingIsIndeterminate: Bool = false

    var compareMode: Bool = false
    var focusedBands: Set<Int> = []
    var errorMessage: String? = nil
    var panelCollapsed: Bool = false
    var isolatedProcessedImage: UIImage? = nil

    @ObservationIgnored var activeSliderCount: Int = 0
    var isAnySliderActive: Bool = false

    func sliderEditingChanged(_ editing: Bool) {
        activeSliderCount += editing ? 1 : -1
        if activeSliderCount < 0 {
            activeSliderCount = 0
        }
        isAnySliderActive = activeSliderCount > 0
    }
}
