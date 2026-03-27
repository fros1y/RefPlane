import Foundation

struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed
    }

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let delta = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % delta)
    }

    mutating func intArray(count: ClosedRange<Int>, values: ClosedRange<Int>) -> [Int] {
        let itemCount = int(in: count)
        return (0..<itemCount).map { _ in int(in: values) }
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let raw = Double(next()) / Double(UInt64.max)
        return range.lowerBound + raw * (range.upperBound - range.lowerBound)
    }

    mutating func uint8() -> UInt8 {
        UInt8(next() % 256)
    }
}
