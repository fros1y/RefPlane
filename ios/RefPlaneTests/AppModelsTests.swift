import Testing
@testable import Underpaint

// MARK: - defaultThresholds

@Test
func defaultThresholdsForSingleLevelIsEmpty() {
    #expect(defaultThresholds(for: 1) == [])
}

@Test
func defaultThresholdsForZeroLevelsIsEmpty() {
    #expect(defaultThresholds(for: 0) == [])
}

@Test
func defaultThresholdsCountEqualsLevelsMinusOne() {
    for seed in 1...20 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let levels = generator.int(in: 1...8)
        let thresholds = defaultThresholds(for: levels)
        #expect(thresholds.count == max(0, levels - 1))
    }
}

@Test
func defaultThresholdsAreEvenlySpaced() {
    #expect(defaultThresholds(for: 2) == [0.5])

    let thirds = defaultThresholds(for: 3)
    #expect(thirds.count == 2)
    #expect(abs(thirds[0] - 1.0 / 3.0) < 1e-10)
    #expect(abs(thirds[1] - 2.0 / 3.0) < 1e-10)

    let quarters = defaultThresholds(for: 4)
    #expect(quarters.count == 3)
    #expect(abs(quarters[0] - 0.25) < 1e-10)
    #expect(abs(quarters[1] - 0.50) < 1e-10)
    #expect(abs(quarters[2] - 0.75) < 1e-10)
}

@Test
func defaultThresholdsAreStrictlyIncreasing() {
    for levels in 2...10 {
        let thresholds = defaultThresholds(for: levels)
        for i in 0..<thresholds.count - 1 {
            #expect(thresholds[i] < thresholds[i + 1])
        }
    }
}

@Test
func defaultThresholdsAreBoundedExclusively() {
    for levels in 2...10 {
        for t in defaultThresholds(for: levels) {
            #expect(t > 0.0 && t < 1.0)
        }
    }
}

// MARK: - MinRegionSize.factor

@Test
func minRegionSizeFactorMapping() {
    #expect(MinRegionSize.off.factor    == nil)
    #expect(MinRegionSize.small.factor  == 0.002)
    #expect(MinRegionSize.medium.factor == 0.005)
    #expect(MinRegionSize.large.factor  == 0.01)
}

// MARK: - QuantizationBias

@Test
func quantizationBiasDirectionMatchesLightAndShadowLabels() {
    let even = QuantizationBias.thresholds(for: 5, bias: 0)
    let lightDetail = QuantizationBias.thresholds(for: 5, bias: -1)
    let shadowDetail = QuantizationBias.thresholds(for: 5, bias: 1)

    #expect(lightDetail.count == even.count)
    #expect(shadowDetail.count == even.count)

    for index in even.indices {
        #expect(lightDetail[index] > even[index])
        #expect(shadowDetail[index] < even[index])
    }

    #expect(QuantizationBias.distribution(for: -1) == .lights)
    #expect(QuantizationBias.distribution(for: 0) == .even)
    #expect(QuantizationBias.distribution(for: 1) == .shadows)
}

@Test
func quantizationBiasDisplayNamesAreQualitative() {
    #expect(QuantizationBias.displayName(for: -0.5) == "Light Detail")
    #expect(QuantizationBias.displayName(for: 0) == "Even")
    #expect(QuantizationBias.displayName(for: 0.5) == "Shadow Detail")
}

@Test
func colorConfigDefaultsPreferHueCoverage() {
    let config = ColorConfig()

    #expect(config.paletteSpread == 1)
}
