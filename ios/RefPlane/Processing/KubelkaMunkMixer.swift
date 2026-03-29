import Foundation

// MARK: - Kubelka-Munk spectral mixing engine

enum KubelkaMunkMixer {

    // MARK: - Core KM math

    /// Reflectance from K/S ratio at a single wavelength.
    /// R = 1 + K/S - sqrt((K/S)^2 + 2*K/S)
    @inline(__always)
    static func reflectance(kOverS: Float) -> Float {
        guard kOverS > 0 else { return 1.0 }
        return 1.0 + kOverS - sqrtf(kOverS * kOverS + 2.0 * kOverS)
    }

    /// K/S from reflectance at a single wavelength (inverse of above).
    /// K/S = (1 - R)^2 / (2 * R)
    @inline(__always)
    static func kOverSFromReflectance(_ r: Float) -> Float {
        let clamped = max(0.001, min(0.999, r))
        let diff = 1.0 - clamped
        return (diff * diff) / (2.0 * clamped)
    }

    /// Mix pigments by linearly blending K/S ratios.
    /// Returns the mixed K/S spectrum (31 values).
    static func mixKOverS(
        pigments: [(kOverS: [Float], concentration: Float)]
    ) -> [Float] {
        guard let first = pigments.first else { return [] }
        let count = first.kOverS.count
        var result = [Float](repeating: 0, count: count)

        for (kOverS, c) in pigments {
            for i in 0..<count {
                result[i] += c * kOverS[i]
            }
        }
        return result
    }

    /// Convert a K/S spectrum to reflectance spectrum.
    static func spectrumFromKOverS(_ kOverS: [Float]) -> [Float] {
        kOverS.map { reflectance(kOverS: $0) }
    }

    // MARK: - Spectral to color conversion

    /// Integrate reflectance spectrum under illuminant and CMFs to get CIE XYZ.
    static func spectrumToXYZ(
        reflectance: [Float],
        cmfX: [Float],
        cmfY: [Float],
        cmfZ: [Float],
        illuminant: [Float]
    ) -> (X: Float, Y: Float, Z: Float) {
        let n = reflectance.count
        var X: Float = 0
        var Y: Float = 0
        var Z: Float = 0
        var normalization: Float = 0

        for i in 0..<n {
            let rI = reflectance[i] * illuminant[i]
            X += rI * cmfX[i]
            Y += rI * cmfY[i]
            Z += rI * cmfZ[i]
            normalization += illuminant[i] * cmfY[i]
        }

        // Normalize so a perfect white reflector gives Y = 1
        guard normalization > 0 else { return (0, 0, 0) }
        let k = 1.0 / normalization
        return (X * k, Y * k, Z * k)
    }

    /// CIE XYZ to linear sRGB (D65 reference white).
    static func xyzToLinearRGB(X: Float, Y: Float, Z: Float) -> LinearRGB {
        // Standard sRGB matrix (IEC 61966-2-1)
        let r =  3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z
        let g = -0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z
        let b =  0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z
        return LinearRGB(r: r, g: g, b: b)
    }

    /// Linear RGB to Oklab (reusing existing sRGB gamma functions + Oklab math).
    static func linearRGBToOklab(_ rgb: LinearRGB) -> OklabColor {
        let rl = max(0, rgb.r)
        let gl = max(0, rgb.g)
        let bl = max(0, rgb.b)

        let lc = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl
        let mc = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl
        let sc = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl

        let l_ = cbrtf(max(0, lc))
        let m_ = cbrtf(max(0, mc))
        let s_ = cbrtf(max(0, sc))

        return OklabColor(
            L:  0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a:  1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b:  0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
        )
    }

    // MARK: - High-level pipeline

    /// Full pipeline: pigment K/S spectrum → Oklab color.
    static func pigmentToOklab(
        kOverS: [Float],
        database: SpectralDatabase
    ) -> OklabColor {
        let refl = spectrumFromKOverS(kOverS)
        let xyz = spectrumToXYZ(
            reflectance: refl,
            cmfX: database.cmfX,
            cmfY: database.cmfY,
            cmfZ: database.cmfZ,
            illuminant: database.illuminantSpd
        )
        let linear = xyzToLinearRGB(X: xyz.X, Y: xyz.Y, Z: xyz.Z)
        return linearRGBToOklab(linear)
    }

    /// Full pipeline: mix multiple pigments at given concentrations → Oklab color.
    static func mixToOklab(
        pigments: [(kOverS: [Float], concentration: Float)],
        database: SpectralDatabase
    ) -> OklabColor {
        let mixedKS = mixKOverS(pigments: pigments)
        return pigmentToOklab(kOverS: mixedKS, database: database)
    }

    /// Full pipeline: mix multiple pigments → sRGB (0-255).
    static func mixToRGB(
        pigments: [(kOverS: [Float], concentration: Float)],
        database: SpectralDatabase
    ) -> (r: UInt8, g: UInt8, b: UInt8) {
        let oklab = mixToOklab(pigments: pigments, database: database)
        return oklabToRGB(oklab)
    }
}
