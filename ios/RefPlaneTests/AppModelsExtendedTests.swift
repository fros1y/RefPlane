import Testing
import SwiftUI
@testable import Underpaint

// MARK: - RefPlaneMode

@Test
func refPlaneModeHasFourCases() {
    #expect(RefPlaneMode.allCases.count == 4)
}

@Test
func refPlaneModeLabelsDefined() {
    #expect(RefPlaneMode.original.label == "Original")
    #expect(RefPlaneMode.tonal.label == "Tonal")
    #expect(RefPlaneMode.value.label == "Value")
    #expect(RefPlaneMode.color.label == "Color")
}

@Test
func refPlaneModeIconNamesDefined() {
    #expect(RefPlaneMode.original.iconName == "photo")
    #expect(RefPlaneMode.tonal.iconName == "circle.lefthalf.filled")
    #expect(RefPlaneMode.value.iconName == "square.stack.3d.up")
    #expect(RefPlaneMode.color.iconName == "paintpalette")
}

@Test
func refPlaneModeIdentifiableUsesRawValue() {
    for mode in RefPlaneMode.allCases {
        #expect(mode.id == mode.rawValue)
    }
}

// MARK: - LineStyle

@Test
func lineStyleAllCasesCount() {
    #expect(LineStyle.allCases.count == 4)
}

@Test
func lineStyleRawValues() {
    #expect(LineStyle.autoContrast.rawValue == "Auto")
    #expect(LineStyle.black.rawValue == "Black")
    #expect(LineStyle.white.rawValue == "White")
    #expect(LineStyle.custom.rawValue == "Custom")
}

// MARK: - GrayscaleConversion

@Test
func grayscaleConversionAllCasesCount() {
    #expect(GrayscaleConversion.allCases.count == 4)
}

@Test
func grayscaleConversionGPUShortcut() {
    #expect(GrayscaleConversion.luminance.usesGPUShortcut == true)
    #expect(GrayscaleConversion.none.usesGPUShortcut == false)
    #expect(GrayscaleConversion.average.usesGPUShortcut == false)
    #expect(GrayscaleConversion.lightness.usesGPUShortcut == false)
}

// MARK: - ThresholdDistribution

@Test
func thresholdDistributionThresholdsCount() {
    for levels in 2...8 {
        for dist in ThresholdDistribution.allCases {
            let thresholds = dist.thresholds(for: levels)
            #expect(thresholds.count == levels - 1)
        }
    }
}

@Test
func thresholdDistributionEvenMatchesDefault() {
    for levels in 2...6 {
        let even = ThresholdDistribution.even.thresholds(for: levels)
        let def = defaultThresholds(for: levels)
        #expect(even.count == def.count)
        for i in even.indices {
            #expect(abs(even[i] - def[i]) < 1e-10)
        }
    }
}

@Test
func thresholdDistributionShadowsShiftLeft() {
    let even = ThresholdDistribution.even.thresholds(for: 5)
    let shadows = ThresholdDistribution.shadows.thresholds(for: 5)
    for i in even.indices {
        #expect(shadows[i] < even[i])
    }
}

@Test
func thresholdDistributionLightsShiftRight() {
    let even = ThresholdDistribution.even.thresholds(for: 5)
    let lights = ThresholdDistribution.lights.thresholds(for: 5)
    for i in even.indices {
        #expect(lights[i] > even[i])
    }
}

@Test
func thresholdDistributionCustomMatchesEven() {
    for levels in 2...5 {
        let custom = ThresholdDistribution.custom.thresholds(for: levels)
        let even = ThresholdDistribution.even.thresholds(for: levels)
        #expect(custom == even)
    }
}

// MARK: - AbstractionMethod

@Test
func abstractionMethodHasOneCase() {
    #expect(AbstractionMethod.allCases.count == 1)
}

@Test
func abstractionMethodAPISRProperties() {
    let method = AbstractionMethod.apisr
    #expect(method.id == "APISR")
    #expect(method.label == "Balanced")
    #expect(method.modelBundleName == "APISR_GRL_x4")
}

@Test
func abstractionMethodProcessingKind() {
    #expect(AbstractionMethod.apisr.processingKind == .superResolution4x)
}

@Test
func abstractionMethodCodableRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let original = AbstractionMethod.apisr
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(AbstractionMethod.self, from: data)
    #expect(decoded == original)
}

@Test
func abstractionMethodDecodesUnknownValueToDefault() throws {
    let json = "\"UnknownMethod\""
    let data = json.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(AbstractionMethod.self, from: data)
    #expect(decoded == .apisr)
}

// MARK: - BackgroundMode

@Test
func backgroundModeAllCases() {
    #expect(BackgroundMode.allCases.count == 4)
    #expect(BackgroundMode.none.rawValue == "No")
    #expect(BackgroundMode.compress.rawValue == "Compress")
    #expect(BackgroundMode.blur.rawValue == "Blur")
    #expect(BackgroundMode.remove.rawValue == "Remove")
}

@Test
func backgroundModeIdentifiable() {
    for mode in BackgroundMode.allCases {
        #expect(mode.id == mode.rawValue)
    }
}

// MARK: - DepthConfig defaults

@Test
func depthConfigDefaults() {
    let config = DepthConfig()
    #expect(config.enabled == false)
    #expect(config.foregroundCutoff == 0.33)
    #expect(config.backgroundCutoff == 0.66)
    #expect(config.effectIntensity == 0.5)
    #expect(config.backgroundMode == .none)
}

// MARK: - ContourConfig defaults

@Test
func contourConfigDefaults() {
    let config = ContourConfig()
    #expect(config.enabled == false)
    #expect(config.levels == 5)
    #expect(config.lineStyle == .autoContrast)
    #expect(config.opacity == 0.7)
}

// MARK: - GridConfig defaults

@Test
func gridConfigDefaults() {
    let config = GridConfig()
    #expect(config.enabled == false)
    #expect(config.divisions == 4)
    #expect(config.showDiagonals == false)
    #expect(config.lineStyle == .autoContrast)
    #expect(config.opacity == 0.7)
}

// MARK: - ValueConfig defaults

@Test
func valueConfigDefaults() {
    let config = ValueConfig()
    #expect(config.grayscaleConversion == .none)
    #expect(config.levels == 3)
    #expect(config.distribution == .even)
    #expect(config.quantizationBias == 0)
    #expect(config.thresholds.count == 2)
}

// MARK: - PigmentPreset

@Test
func pigmentPresetAllCasesCount() {
    #expect(PigmentPreset.allCases.count == 5)
}

@Test
func pigmentPresetZornHasFourPigments() {
    #expect(PigmentPreset.zorn.pigmentIDs.count == 4)
    #expect(PigmentPreset.zorn.pigmentIDs.contains("yellow_ochre"))
    #expect(PigmentPreset.zorn.pigmentIDs.contains("cad_red_medium"))
    #expect(PigmentPreset.zorn.pigmentIDs.contains("carbon_black"))
    #expect(PigmentPreset.zorn.pigmentIDs.contains("titanium_white"))
}

@Test
func pigmentPresetPrimaryHasEightPigments() {
    #expect(PigmentPreset.primary.pigmentIDs.count == 8)
}

@Test
func pigmentPresetWarmHasTenPigments() {
    #expect(PigmentPreset.warm.pigmentIDs.count == 10)
}

@Test
func pigmentPresetCoolHasTenPigments() {
    #expect(PigmentPreset.cool.pigmentIDs.count == 10)
}

@Test
func pigmentPresetAllContainsAllEssential() {
    let allIDs = PigmentPreset.all.pigmentIDs
    // All essential pigments should be included
    for pigment in SpectralDataStore.essentialPigments {
        #expect(allIDs.contains(pigment.id))
    }
}

@Test
func pigmentPresetIdentifiable() {
    for preset in PigmentPreset.allCases {
        #expect(preset.id == preset.rawValue)
    }
}

// MARK: - QuantizationBias extended

@Test
func quantizationBiasClampedRespectsRange() {
    #expect(QuantizationBias.clamped(-5.0) == -1.0)
    #expect(QuantizationBias.clamped(5.0) == 1.0)
    #expect(QuantizationBias.clamped(0.5) == 0.5)
}

@Test
func quantizationBiasLuminanceExponentNeutralIsOne() {
    let exp = QuantizationBias.luminanceExponent(for: 0)
    #expect(abs(exp - 1.0) < 1e-5)
}

@Test
func quantizationBiasThresholdsSingleLevel() {
    #expect(QuantizationBias.thresholds(for: 1, bias: 0).isEmpty)
}

@Test
func quantizationBiasThresholdsStrictlyIncreasing() {
    for bias in stride(from: -1.0, through: 1.0, by: 0.5) {
        for levels in 2...8 {
            let t = QuantizationBias.thresholds(for: levels, bias: bias)
            for i in 0..<t.count - 1 {
                #expect(t[i] < t[i + 1])
            }
        }
    }
}

@Test
func quantizationBiasThresholdsBounded() {
    for bias in stride(from: -1.0, through: 1.0, by: 0.5) {
        for levels in 2...8 {
            for t in QuantizationBias.thresholds(for: levels, bias: bias) {
                #expect(t > 0.0 && t < 1.0)
            }
        }
    }
}

// MARK: - SourceImageMetadata

@Test
func sourceImageMetadataEmpty() {
    let meta = SourceImageMetadata.empty
    #expect(meta.properties.isEmpty)
    #expect(meta.uniformTypeIdentifier == nil)
}

// MARK: - ImportedImagePayload

@Test
func importedImagePayloadDefaultMetadata() {
    let image = TestImageFactory.makeSolid(width: 1, height: 1, color: .red)
    let payload = ImportedImagePayload(image: image)
    #expect(payload.metadata.properties.isEmpty)
    #expect(payload.embeddedDepthMap == nil)
}

// MARK: - PurchaseState

@Test
func purchaseStateEquatable() {
    #expect(PurchaseState.unknown == PurchaseState.unknown)
    #expect(PurchaseState.locked == PurchaseState.locked)
    #expect(PurchaseState.unlocked == PurchaseState.unlocked)
    #expect(PurchaseState.purchasing == PurchaseState.purchasing)
    #expect(PurchaseState.pending == PurchaseState.pending)
    #expect(PurchaseState.error == PurchaseState.error)
    #expect(PurchaseState.locked != PurchaseState.unlocked)
}

// MARK: - ProcessingError

@Test
func processingErrorDescription() {
    let error = ProcessingError.conversionFailed
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("processing failed"))
}

// MARK: - MetalError

@Test
func metalErrorDescription() {
    let error = MetalError.functionNotFound("test_fn")
    #expect(error.errorDescription != nil)
    #expect(error.errorDescription!.contains("test_fn"))
}

// MARK: - AbstractionError

@Test
func abstractionErrorDescriptions() {
    let e1 = AbstractionError.modelUnavailable(.apisr)
    #expect(e1.errorDescription != nil)

    let e2 = AbstractionError.unsupportedModelContract(.apisr)
    #expect(e2.errorDescription != nil)

    let e3 = AbstractionError.inferenceFailed(.apisr)
    #expect(e3.errorDescription != nil)
}
