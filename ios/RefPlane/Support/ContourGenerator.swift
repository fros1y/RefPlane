import UIKit

// MARK: - Marching squares contour generator

enum ContourGenerator {

    /// Generate contour line segments from a depth map using marching squares.
    ///
    /// Segments are returned in normalized [0,1] coordinates matching the
    /// `GridLineSegment` convention used by the grid overlay.
    ///
    /// - Parameters:
    ///   - depthMap: Grayscale depth map image.
    ///   - levels: Number of isoline levels (2–12).
    ///   - depthRange: The actual min/max depth values in the map.
    ///   - backgroundCutoff: Depth values ≥ this are treated as background (skipped).
    /// - Returns: Array of normalized line segments.
    static func generateSegments(
        depthMap: UIImage,
        levels: Int,
        depthRange: ClosedRange<Double>,
        backgroundCutoff: Double
    ) -> [GridLineSegment] {
        let gridW = 200
        let gridH = 200
        let vertW = gridW + 1
        let vertH = gridH + 1

        // Sample the depth map into a vertex grid
        guard let vertices = sampleDepthMap(depthMap, width: vertW, height: vertH) else {
            return []
        }

        // Compute thresholds evenly spaced inside the visible (non-background) zone
        let lo = depthRange.lowerBound
        let hi = min(backgroundCutoff, depthRange.upperBound)
        guard hi > lo, levels > 0 else { return [] }

        var thresholds: [Double] = []
        thresholds.reserveCapacity(levels)
        for i in 0..<levels {
            thresholds.append(lo + (hi - lo) * Double(i + 1) / Double(levels + 1))
        }

        // Run marching squares on the depth field
        return traceIsolines(
            field: vertices,
            vertW: vertW, vertH: vertH,
            gridW: gridW, gridH: gridH,
            thresholds: thresholds,
            backgroundMask: vertices,
            backgroundCutoff: backgroundCutoff
        )
    }

    // MARK: - Depth map sampling

    private static func sampleDepthMap(_ image: UIImage, width: Int, height: Int) -> [Double]? {
        guard let cgImage = image.cgImage else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixels.map { Double($0) / 255.0 }
    }

    // MARK: - Isoline tracing (shared by depth and stream fields)

    /// Trace isolines on a scalar field using marching squares.
    /// `backgroundMask` + `backgroundCutoff` are used to skip background cells
    /// (always evaluated against the depth vertices, even for the stream field).
    private static func traceIsolines(
        field: [Double],
        vertW: Int, vertH: Int,
        gridW: Int, gridH: Int,
        thresholds: [Double],
        backgroundMask: [Double],
        backgroundCutoff: Double
    ) -> [GridLineSegment] {
        var segments: [GridLineSegment] = []
        segments.reserveCapacity(thresholds.count * gridW * 2)

        let invW = 1.0 / Double(gridW)
        let invH = 1.0 / Double(gridH)

        for row in 0..<gridH {
            for col in 0..<gridW {
                // Skip cells entirely in the background zone (using depth mask)
                let mTL = backgroundMask[row * vertW + col]
                let mTR = backgroundMask[row * vertW + col + 1]
                let mBL = backgroundMask[(row + 1) * vertW + col]
                let mBR = backgroundMask[(row + 1) * vertW + col + 1]
                if mTL >= backgroundCutoff && mTR >= backgroundCutoff &&
                   mBL >= backgroundCutoff && mBR >= backgroundCutoff {
                    continue
                }

                let tl = field[row * vertW + col]
                let tr = field[row * vertW + col + 1]
                let bl = field[(row + 1) * vertW + col]
                let br = field[(row + 1) * vertW + col + 1]

                for t in thresholds {
                    let caseIndex = (tl < t ? 8 : 0) |
                                    (tr < t ? 4 : 0) |
                                    (br < t ? 2 : 0) |
                                    (bl < t ? 1 : 0)

                    guard caseIndex != 0 && caseIndex != 15 else { continue }

                    let cellSegments = marchingSquaresSegments(
                        caseIndex: caseIndex,
                        col: col, row: row,
                        tl: tl, tr: tr, bl: bl, br: br,
                        threshold: t
                    )

                    for (p0, p1) in cellSegments {
                        let seg = GridLineSegment(
                            start: CGPoint(x: p0.x * invW, y: p0.y * invH),
                            end: CGPoint(x: p1.x * invW, y: p1.y * invH)
                        )
                        if !seg.isDegenerate {
                            segments.append(seg)
                        }
                    }
                }
            }
        }

        return segments
    }

    // MARK: - Marching squares lookup

    /// Returns 0, 1, or 2 segment endpoint pairs for a single cell.
    /// Coordinates are in grid-cell space (col, row) with sub-cell interpolation.
    private static func marchingSquaresSegments(
        caseIndex: Int,
        col: Int, row: Int,
        tl: Double, tr: Double, bl: Double, br: Double,
        threshold t: Double
    ) -> [(CGPoint, CGPoint)] {
        // Edge interpolation helpers
        let c = Double(col)
        let r = Double(row)

        // Top edge: between tl and tr
        func top() -> CGPoint {
            let frac = safeLerp(t, tl, tr)
            return CGPoint(x: c + frac, y: r)
        }
        // Bottom edge: between bl and br
        func bottom() -> CGPoint {
            let frac = safeLerp(t, bl, br)
            return CGPoint(x: c + frac, y: r + 1)
        }
        // Left edge: between tl and bl
        func left() -> CGPoint {
            let frac = safeLerp(t, tl, bl)
            return CGPoint(x: c, y: r + frac)
        }
        // Right edge: between tr and br
        func right() -> CGPoint {
            let frac = safeLerp(t, tr, br)
            return CGPoint(x: c + 1, y: r + frac)
        }

        // 16-case lookup table for marching squares
        // Bit layout: tl=8, tr=4, br=2, bl=1  (bit set when value < threshold)
        switch caseIndex {
        case 0, 15:
            return []
        case 1:  // bl
            return [(left(), bottom())]
        case 2:  // br
            return [(bottom(), right())]
        case 3:  // bl, br
            return [(left(), right())]
        case 4:  // tr
            return [(top(), right())]
        case 5:  // tr, bl — saddle
            let avg = (tl + tr + bl + br) / 4.0
            if avg < t {
                return [(top(), right()), (left(), bottom())]
            } else {
                return [(top(), left()), (bottom(), right())]
            }
        case 6:  // tr, br
            return [(top(), bottom())]
        case 7:  // tr, br, bl
            return [(top(), left())]
        case 8:  // tl
            return [(top(), left())]
        case 9:  // tl, bl
            return [(top(), bottom())]
        case 10: // tl, br — saddle
            let avg = (tl + tr + bl + br) / 4.0
            if avg < t {
                return [(top(), left()), (bottom(), right())]
            } else {
                return [(top(), right()), (left(), bottom())]
            }
        case 11: // tl, bl, br
            return [(top(), right())]
        case 12: // tl, tr
            return [(left(), right())]
        case 13: // tl, tr, bl
            return [(bottom(), right())]
        case 14: // tl, tr, br
            return [(left(), bottom())]
        default:
            return []
        }
    }

    /// Safe linear interpolation fraction: (threshold - a) / (b - a), clamped to [0,1].
    private static func safeLerp(_ threshold: Double, _ a: Double, _ b: Double) -> Double {
        let denom = b - a
        guard abs(denom) > 1e-12 else { return 0.5 }
        return max(0, min(1, (threshold - a) / denom))
    }
}
