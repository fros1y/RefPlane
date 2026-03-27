import Testing
@testable import Underpaint

// MARK: - linearizeSRGB / delinearizeSRGB

@Test
func linearizeSRGBAndDelinearizeRoundtrip() {
    for seed in 1...200 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let c = Float(generator.double(in: 0.0...1.0))
        let roundtripped = delinearizeSRGB(linearizeSRGB(c))
        #expect(abs(roundtripped - c) < 1e-5)
    }
}

@Test
func linearizeSRGBBoundaryValues() {
    // Exact endpoints map to themselves
    #expect(abs(linearizeSRGB(0.0)) < 1e-9)
    #expect(abs(linearizeSRGB(1.0) - 1.0) < 1e-5)
    #expect(abs(delinearizeSRGB(0.0)) < 1e-9)
    #expect(abs(delinearizeSRGB(1.0) - 1.0) < 1e-5)

    // Low-end branch: c / 12.92 for c <= 0.04045
    let low: Float = 0.04
    let expectedLow = low / 12.92
    #expect(abs(linearizeSRGB(low) - expectedLow) < 1e-6)

    // Low-end branch for delinearize: c * 12.92 for c <= 0.0031308
    let lowD: Float = 0.003
    let expectedLowD = lowD * 12.92
    #expect(abs(delinearizeSRGB(lowD) - expectedLowD) < 1e-6)
}

// MARK: - rgbToOklab / oklabToRGB

@Test
func rgbToOklabAndBackRoundtrip() {
    for seed in 1...200 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let r = generator.uint8()
        let g = generator.uint8()
        let b = generator.uint8()
        let lab = rgbToOklab(r: r, g: g, b: b)
        let (rOut, gOut, bOut) = oklabToRGB(lab)
        #expect(abs(Int(rOut) - Int(r)) <= 1)
        #expect(abs(Int(gOut) - Int(g)) <= 1)
        #expect(abs(Int(bOut) - Int(b)) <= 1)
    }
}

@Test
func rgbToOklabKnownColors() {
    // Black: L should be near 0, a and b near 0
    let black = rgbToOklab(r: 0, g: 0, b: 0)
    #expect(black.L < 0.001)
    #expect(abs(black.a) < 0.001)
    #expect(abs(black.b) < 0.001)

    // White: L near 1, a and b near 0
    let white = rgbToOklab(r: 255, g: 255, b: 255)
    #expect(abs(white.L - 1.0) < 0.002)
    #expect(abs(white.a) < 0.002)
    #expect(abs(white.b) < 0.002)

    // L must be in [0, 1] for in-gamut sRGB colors
    let red = rgbToOklab(r: 255, g: 0, b: 0)
    #expect(red.L >= 0 && red.L <= 1.0)
    let green = rgbToOklab(r: 0, g: 255, b: 0)
    #expect(green.L >= 0 && green.L <= 1.0)
    let blue = rgbToOklab(r: 0, g: 0, b: 255)
    #expect(blue.L >= 0 && blue.L <= 1.0)
}

// MARK: - oklabDistance

@Test
func oklabDistanceIsZeroForIdenticalColors() {
    let colors: [OklabColor] = [
        OklabColor(L: 0.5, a: 0.1,  b: -0.1),
        OklabColor(L: 0.0, a: 0.0,  b: 0.0),
        OklabColor(L: 1.0, a: 0.2,  b: 0.3),
        OklabColor(L: 0.3, a: -0.2, b: 0.15),
    ]
    for c in colors {
        #expect(oklabDistance(c, c) == 0.0)
    }
}

@Test
func oklabDistanceIsSymmetric() {
    for seed in 1...200 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let a = OklabColor(
            L: Float(generator.double(in: 0.0...1.0)),
            a: Float(generator.double(in: -0.5...0.5)),
            b: Float(generator.double(in: -0.5...0.5))
        )
        let b = OklabColor(
            L: Float(generator.double(in: 0.0...1.0)),
            a: Float(generator.double(in: -0.5...0.5)),
            b: Float(generator.double(in: -0.5...0.5))
        )
        #expect(oklabDistance(a, b) == oklabDistance(b, a))
    }
}

// MARK: - oklabDistanceColorWeighted

@Test
func oklabDistanceColorWeightedZeroLWeightIgnoresLuminance() {
    // Two colors that differ only in L; with lWeight=0, the distance should be 0
    let a = OklabColor(L: 0.0, a: 0.1, b: 0.05)
    let b = OklabColor(L: 1.0, a: 0.1, b: 0.05)
    let dist = oklabDistanceColorWeighted(a, b, lWeight: 0.0)
    #expect(dist < 1e-10)
}

@Test
func oklabDistanceColorWeightedRespectsLWeight() {
    // Colors differing only in L by 1.0; distance = (dL * lWeight)^2
    let a = OklabColor(L: 0.0, a: 0.0, b: 0.0)
    let b = OklabColor(L: 1.0, a: 0.0, b: 0.0)
    let lWeight: Float = 0.5
    let dist = oklabDistanceColorWeighted(a, b, lWeight: lWeight)
    let expected = lWeight * lWeight   // (1.0 * 0.5)^2 = 0.25
    #expect(abs(dist - expected) < 1e-6)
}
