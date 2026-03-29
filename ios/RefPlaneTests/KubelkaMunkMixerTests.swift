import Testing
import Foundation
@testable import Underpaint

// MARK: - KM reflectance formula

@Test
func reflectanceFromKOverS_knownValues() {
    // K/S = 0 → R = 1.0 (perfect white)
    #expect(abs(KubelkaMunkMixer.reflectance(kOverS: 0) - 1.0) < 1e-6)

    // K/S = ∞ → R → 0 (perfect black)
    #expect(KubelkaMunkMixer.reflectance(kOverS: 1000) < 0.001)

    // K/S = 1 → R = 1 + 1 - sqrt(1 + 2) = 2 - sqrt(3) ≈ 0.2679
    let expected: Float = 2.0 - sqrtf(3.0)
    #expect(abs(KubelkaMunkMixer.reflectance(kOverS: 1.0) - expected) < 1e-5)
}

@Test
func kOverSRoundtrip() {
    // reflectance → K/S → reflectance should roundtrip
    let testValues: [Float] = [0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99]
    for r in testValues {
        let ks = KubelkaMunkMixer.kOverSFromReflectance(r)
        let rBack = KubelkaMunkMixer.reflectance(kOverS: ks)
        #expect(abs(rBack - r) < 0.005, "Roundtrip failed for R=\(r): got \(rBack)")
    }
}

// MARK: - Mixing linearity

@Test
func mixKOverS_linearBlend() {
    let ks1: [Float] = [1.0, 2.0, 3.0]
    let ks2: [Float] = [5.0, 6.0, 7.0]

    let mixed = KubelkaMunkMixer.mixKOverS(pigments: [
        (kOverS: ks1, concentration: 0.5),
        (kOverS: ks2, concentration: 0.5)
    ])

    #expect(mixed.count == 3)
    #expect(abs(mixed[0] - 3.0) < 1e-5)
    #expect(abs(mixed[1] - 4.0) < 1e-5)
    #expect(abs(mixed[2] - 5.0) < 1e-5)
}

@Test
func mixKOverS_singlePigmentAtFullConcentration() {
    let ks: [Float] = [2.0, 4.0, 6.0]
    let mixed = KubelkaMunkMixer.mixKOverS(pigments: [
        (kOverS: ks, concentration: 1.0)
    ])
    for i in 0..<ks.count {
        #expect(abs(mixed[i] - ks[i]) < 1e-6)
    }
}

// MARK: - XYZ normalization

@Test
func spectrumToXYZ_perfectWhiteGivesYOne() {
    let db = SpectralDataStore.shared
    // Perfect reflector: R = 1.0 at all wavelengths
    let white = [Float](repeating: 1.0, count: db.wavelengths.count)
    let xyz = KubelkaMunkMixer.spectrumToXYZ(
        reflectance: white,
        cmfX: db.cmfX, cmfY: db.cmfY, cmfZ: db.cmfZ,
        illuminant: db.illuminantSpd
    )
    // Y should be 1.0 for a perfect white reflector under any illuminant
    #expect(abs(xyz.Y - 1.0) < 0.01, "Perfect white Y=\(xyz.Y), expected ~1.0")
}

@Test
func spectrumToXYZ_zeroReflectanceGivesZero() {
    let db = SpectralDataStore.shared
    let black = [Float](repeating: 0.0, count: db.wavelengths.count)
    let xyz = KubelkaMunkMixer.spectrumToXYZ(
        reflectance: black,
        cmfX: db.cmfX, cmfY: db.cmfY, cmfZ: db.cmfZ,
        illuminant: db.illuminantSpd
    )
    #expect(abs(xyz.X) < 1e-6)
    #expect(abs(xyz.Y) < 1e-6)
    #expect(abs(xyz.Z) < 1e-6)
}

// MARK: - Full pipeline: known pigments

@Test
func pigmentToOklab_darkPigmentHasLowL() {
    let db = SpectralDataStore.shared
    guard let marsBlack = db.pigments.first(where: { $0.id == "mars_black" }) else {
        Issue.record("Mars Black not found in database")
        return
    }
    let color = KubelkaMunkMixer.pigmentToOklab(kOverS: marsBlack.kOverS, database: db)
    // Mars Black should have very low lightness (CIE L*≈25 → Oklab L≈0.36)
    #expect(color.L < 0.4, "Mars Black L=\(color.L), expected < 0.4")
}

@Test
func pigmentToOklab_lightPigmentHasHighL() {
    let db = SpectralDataStore.shared
    guard let titanBuff = db.pigments.first(where: { $0.id == "titan_buff" }) else {
        Issue.record("Titan Buff not found in database")
        return
    }
    let color = KubelkaMunkMixer.pigmentToOklab(kOverS: titanBuff.kOverS, database: db)
    // Titan Buff is a light warm off-white
    #expect(color.L > 0.7, "Titan Buff L=\(color.L), expected > 0.7")
}

@Test
func pigmentToOklab_ultramarine_isBlue() {
    let db = SpectralDataStore.shared
    guard let ultramarine = db.pigments.first(where: { $0.id == "ultramarine_blue" }) else {
        Issue.record("Ultramarine Blue not found in database")
        return
    }
    let color = KubelkaMunkMixer.pigmentToOklab(kOverS: ultramarine.kOverS, database: db)
    // Ultramarine should be in the blue region: negative b in Oklab
    #expect(color.b < -0.05, "Ultramarine b=\(color.b), expected strongly negative")
}

@Test
func pigmentToOklab_yellowOchre_isWarmYellow() {
    let db = SpectralDataStore.shared
    guard let ochre = db.pigments.first(where: { $0.id == "yellow_ochre" }) else {
        Issue.record("Yellow Ochre not found in database")
        return
    }
    let color = KubelkaMunkMixer.pigmentToOklab(kOverS: ochre.kOverS, database: db)
    // Yellow Ochre should have positive b (yellow) and slightly positive a (warm)
    #expect(color.b > 0.03, "Yellow Ochre b=\(color.b), expected positive")
}

// MARK: - Mixing produces intermediate colors

@Test
func mixToOklab_blendIsIntermediate() {
    let db = SpectralDataStore.shared
    guard let blue = db.pigments.first(where: { $0.id == "ultramarine_blue" }),
          let yellow = db.pigments.first(where: { $0.id == "yellow_ochre" }) else {
        Issue.record("Required pigments not found")
        return
    }

    let blueColor = KubelkaMunkMixer.pigmentToOklab(kOverS: blue.kOverS, database: db)
    let yellowColor = KubelkaMunkMixer.pigmentToOklab(kOverS: yellow.kOverS, database: db)
    let mixColor = KubelkaMunkMixer.mixToOklab(
        pigments: [
            (kOverS: blue.kOverS, concentration: 0.5),
            (kOverS: yellow.kOverS, concentration: 0.5)
        ],
        database: db
    )

    // The mix lightness should be between (or near) the two pure pigments
    // Note: KM mixing is subtractive, so the mix may be darker than both
    let minL = min(blueColor.L, yellowColor.L)
    let maxL = max(blueColor.L, yellowColor.L)
    // Allow it to be somewhat darker due to subtractive mixing
    #expect(mixColor.L > minL * 0.5, "Mix L=\(mixColor.L) too dark vs min=\(minL)")
    #expect(mixColor.L < maxL + 0.1, "Mix L=\(mixColor.L) too light vs max=\(maxL)")
}

// MARK: - linearRGBToOklab consistency

@Test
func linearRGBToOklab_matchesByteVersion() {
    // Compare linearRGBToOklab with rgbToOklab for a known color
    let sR: UInt8 = 128
    let sG: UInt8 = 64
    let sB: UInt8 = 200
    let fromBytes = rgbToOklab(r: sR, g: sG, b: sB)

    let rLin = linearizeSRGB(Float(sR) / 255.0)
    let gLin = linearizeSRGB(Float(sG) / 255.0)
    let bLin = linearizeSRGB(Float(sB) / 255.0)
    let fromLinear = KubelkaMunkMixer.linearRGBToOklab(LinearRGB(r: rLin, g: gLin, b: bLin))

    #expect(abs(fromBytes.L - fromLinear.L) < 1e-4)
    #expect(abs(fromBytes.a - fromLinear.a) < 1e-4)
    #expect(abs(fromBytes.b - fromLinear.b) < 1e-4)
}
