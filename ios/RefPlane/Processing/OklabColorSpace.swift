import Foundation

// MARK: - Oklab color space math

struct OklabColor {
    var L: Float
    var a: Float
    var b: Float
}

struct LinearRGB {
    var r: Float
    var g: Float
    var b: Float
}

// Linearize an sRGB channel value (0-1 range)
@inline(__always)
func linearizeSRGB(_ c: Float) -> Float {
    c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
}

// Delinearize a linear-light channel back to sRGB (0-1 range)
@inline(__always)
func delinearizeSRGB(_ c: Float) -> Float {
    c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1.0 / 2.4) - 0.055
}

// Convert sRGB (0-255 bytes) to Oklab
func rgbToOklab(r: UInt8, g: UInt8, b: UInt8) -> OklabColor {
    let rl = linearizeSRGB(Float(r) / 255.0)
    let gl = linearizeSRGB(Float(g) / 255.0)
    let bl = linearizeSRGB(Float(b) / 255.0)

    let lc = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl
    let mc = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl
    let sc = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl

    let l_ = cbrtf(lc)
    let m_ = cbrtf(mc)
    let s_ = cbrtf(sc)

    return OklabColor(
        L:  0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        a:  1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        b:  0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    )
}

// Convert Oklab back to sRGB (0-255 clamped)
func oklabToRGB(_ lab: OklabColor) -> (r: UInt8, g: UInt8, b: UInt8) {
    let l_ = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b
    let m_ = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b
    let s_ = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b

    let l = l_ * l_ * l_
    let m = m_ * m_ * m_
    let s = s_ * s_ * s_

    let rl =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    let gl = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    let rs = delinearizeSRGB(rl)
    let gs = delinearizeSRGB(gl)
    let bs = delinearizeSRGB(bl)

    return (
        r: UInt8(max(0, min(255, Int(rs * 255 + 0.5)))),
        g: UInt8(max(0, min(255, Int(gs * 255 + 0.5)))),
        b: UInt8(max(0, min(255, Int(bs * 255 + 0.5))))
    )
}

// Distance in Oklab with de-emphasized L (for color-region assignment)
@inline(__always)
func oklabDistanceColorWeighted(_ a: OklabColor, _ b: OklabColor, lWeight: Float = 0.1) -> Float {
    let dL = (a.L - b.L) * lWeight
    let da = a.a - b.a
    let db = a.b - b.b
    return dL * dL + da * da + db * db
}

// Standard Oklab Euclidean distance
@inline(__always)
func oklabDistance(_ a: OklabColor, _ b: OklabColor) -> Float {
    let dL = a.L - b.L
    let da = a.a - b.a
    let db = a.b - b.b
    return dL * dL + da * da + db * db
}
