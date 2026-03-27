import Foundation

enum ThresholdUtilities {
    static func sanitized(_ thresholds: [Double], levels: Int) -> [Double] {
        let expectedHandles = max(0, levels - 1)
        var safe = thresholds
            .filter { $0 >= 0 && $0 <= 1 }
            .sorted()

        while safe.count < expectedHandles {
            safe.append(Double(safe.count + 1) / Double(expectedHandles + 1))
        }

        safe.sort()
        if safe.count > expectedHandles {
            safe = Array(safe.prefix(expectedHandles))
        }

        return safe
    }

    static func normalizedFloats(_ thresholds: [Double], levels: Int) -> [Float] {
        sanitized(thresholds, levels: levels)
            .filter { $0 > 0 && $0 < 1 }
            .map(Float.init)
    }
}
