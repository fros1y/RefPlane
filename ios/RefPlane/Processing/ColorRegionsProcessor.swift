import UIKit
import SwiftUI

// MARK: - Color Regions pipeline

enum ColorRegionsProcessor {

    struct Result {
        let image: UIImage
        /// Centroids in SwiftUI Color, grouped by band index
        let palette: [Color]
        let paletteBands: [Int]
    }

    static func process(image: UIImage, config: ColorConfig) -> Result? {
        guard let (pixels, width, height) = image.toPixelData() else { return nil }
        let total = width * height
        let bands = max(2, min(6, config.bands))
        let cpb   = max(1, min(4, config.colorsPerBand))

        // 1. Convert all pixels to Oklab
        var lab = [OklabColor](repeating: OklabColor(L: 0, a: 0, b: 0), count: total)
        for i in 0..<total {
            let base = i * 4
            lab[i] = rgbToOklab(r: pixels[base], g: pixels[base+1], b: pixels[base+2])
        }

        // 2. Assign each pixel to a brightness band using L-thresholds
        let thresholds = config.thresholds.map { Float($0) }
        var bandAssign = [Int](repeating: 0, count: total)
        for i in 0..<total {
            var bnd = 0
            for t in thresholds { if lab[i].L >= t { bnd += 1 } }
            bandAssign[i] = min(bnd, bands - 1)
        }

        // 3. Within each band, run k-means on chromatic (a,b) values
        var centroidsByBand: [[OklabColor]] = []
        var assignByBand: [[Int]] = Array(repeating: [], count: bands)

        // global label: band * cpb + clusterWithinBand
        var globalLabel = [Int32](repeating: 0, count: total)

        for bnd in 0..<bands {
            var indices = [Int]()
            for i in 0..<total { if bandAssign[i] == bnd { indices.append(i) } }

            let bandLab = indices.map { lab[$0] }
            let k = min(cpb, bandLab.count)
            var centroids: [OklabColor]
            var assignments: [Int]

            if k < 1 || bandLab.isEmpty {
                // No pixels in this band; use midpoint
                let midL = bands > 1 ? Float(bnd) / Float(bands - 1) : 0.5
                centroids = [OklabColor(L: midL, a: 0, b: 0)]
                assignments = []
            } else {
                let result = KMeansClusterer.cluster(points: bandLab, k: k, lWeight: 0.1)
                centroids = result.centroids
                assignments = result.assignments
            }

            // Apply warm/cool emphasis if needed
            if config.warmCoolEmphasis != 0 {
                let angle = Float(config.warmCoolEmphasis) * Float.pi / 4  // up to 45° hue shift
                centroids = centroids.map { c in
                    let r = sqrtf(c.a * c.a + c.b * c.b)
                    let theta = atan2f(c.b, c.a) + angle
                    return OklabColor(L: c.L, a: r * cosf(theta), b: r * sinf(theta))
                }
            }

            centroidsByBand.append(centroids)
            for (j, pi) in indices.enumerated() {
                let clusterIdx = assignments.isEmpty ? 0 : min(assignments[j], centroids.count - 1)
                globalLabel[pi] = Int32(bnd * cpb + clusterIdx)
                assignByBand[bnd].append(clusterIdx)
            }
        }

        // 4. Optional region cleanup using global labels
        if let factor = config.minRegionSize.factor {
            RegionCleaner.clean(labels: &globalLabel, width: width, height: height, minFactor: factor)
        }

        // 5. Build output image and palette
        var out = [UInt8](repeating: 255, count: total * 4)
        var palette: [Color] = []
        var paletteBands: [Int] = []

        // Flatten centroid table
        var flatCentroids: [OklabColor] = []
        for bnd in 0..<bands {
            let cs = centroidsByBand[bnd]
            for c in cs {
                let (r, g, b) = oklabToRGB(c)
                palette.append(Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255))
                paletteBands.append(bnd)
                flatCentroids.append(c)
            }
        }

        // Map each pixel to nearest centroid (after cleanup, labels may cross bands)
        for i in 0..<total {
            var lbl = Int(globalLabel[i])
            if lbl < 0 || lbl >= flatCentroids.count { lbl = 0 }
            let c = flatCentroids[lbl]
            let (r, g, b) = oklabToRGB(c)
            let base = i * 4
            out[base]     = r
            out[base + 1] = g
            out[base + 2] = b
            out[base + 3] = pixels[base + 3]
        }

        guard let img = UIImage.fromPixelData(out, width: width, height: height) else { return nil }
        return Result(image: img, palette: palette, paletteBands: paletteBands)
    }
}
