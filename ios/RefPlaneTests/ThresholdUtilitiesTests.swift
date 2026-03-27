import Testing
@testable import Underpaint

@Test
func sanitizedThresholdsRemainBoundedSizedAndOrdered() {
    for seed in 1...200 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let rawValues = generator.intArray(count: 0...12, values: -100...200)
        let levels = generator.int(in: 1...10)
        let thresholds = rawValues.map { Double($0) / 100.0 }
        let sanitized = ThresholdUtilities.sanitized(thresholds, levels: levels)

        #expect(sanitized.count == max(0, levels - 1))
        #expect(sanitized.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(isNonDecreasing(sanitized))
    }
}

@Test
func sanitizedThresholdsAreIdempotent() {
    for seed in 201...400 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let rawValues = generator.intArray(count: 0...12, values: -100...200)
        let levels = generator.int(in: 1...10)
        let thresholds = rawValues.map { Double($0) / 100.0 }
        let sanitized = ThresholdUtilities.sanitized(thresholds, levels: levels)
        #expect(ThresholdUtilities.sanitized(sanitized, levels: levels) == sanitized)
    }
}

private func isNonDecreasing(_ values: [Double]) -> Bool {
    zip(values, values.dropFirst()).allSatisfy(<=)
}
