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
        backgroundCutoff: Double,
        includeOrthogonal: Bool = false
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
        var segments = traceIsolines(
            field: vertices,
            vertW: vertW, vertH: vertH,
            gridW: gridW, gridH: gridH,
            thresholds: thresholds,
            backgroundMask: vertices,
            backgroundCutoff: backgroundCutoff
        )

        // Optionally add orthogonal contours (stream function isolines)
        if includeOrthogonal {
            let streamField = computeStreamFunction(
                vertices: vertices,
                vertW: vertW, vertH: vertH,
                backgroundCutoff: backgroundCutoff
            )
            let orthoThresholds = computeOrthogonalThresholds(
                field: streamField,
                backgroundMask: vertices,
                backgroundCutoff: backgroundCutoff,
                levels: levels
            )
            if !orthoThresholds.isEmpty {
                let orthoSegs = traceIsolines(
                    field: streamField,
                    vertW: vertW, vertH: vertH,
                    gridW: gridW, gridH: gridH,
                    thresholds: orthoThresholds,
                    backgroundMask: vertices,
                    backgroundCutoff: backgroundCutoff
                )
                segments.append(contentsOf: orthoSegs)
            }
        }

        return segments
    }

    /// Generate a regular horizontal/vertical image-space grid that is warped by
    /// depth using a simple perspective camera model.
    static func generateProjectedGridSegments(
        depthMap: UIImage,
        levels: Int,
        depthRange: ClosedRange<Double>,
        backgroundCutoff: Double,
        depthScale: Double
    ) -> [GridLineSegment] {
        let gridResolution = 200
        let lineCount = max(2, levels)
        let sampleCount = gridResolution + 1

        guard let vertices = sampleDepthMap(depthMap, width: sampleCount, height: sampleCount) else {
            return []
        }

        let visibleDepthRange = max(1e-6, min(backgroundCutoff, depthRange.upperBound) - depthRange.lowerBound)
        let camera = ProjectedGridCamera(depthScale: max(0, depthScale))

        var segments: [GridLineSegment] = []
        segments.reserveCapacity((lineCount + 1) * gridResolution * 2)

        for index in 0...lineCount {
            let fixed = Double(index) / Double(lineCount)
            appendProjectedPolyline(
                segments: &segments,
                vertices: vertices,
                sampleCount: sampleCount,
                sampleSteps: gridResolution,
                backgroundCutoff: backgroundCutoff,
                depthLowerBound: depthRange.lowerBound,
                visibleDepthRange: visibleDepthRange,
                camera: camera,
                pointAt: { varying in CGPoint(x: fixed, y: varying) }
            )
            appendProjectedPolyline(
                segments: &segments,
                vertices: vertices,
                sampleCount: sampleCount,
                sampleSteps: gridResolution,
                backgroundCutoff: backgroundCutoff,
                depthLowerBound: depthRange.lowerBound,
                visibleDepthRange: visibleDepthRange,
                camera: camera,
                pointAt: { varying in CGPoint(x: varying, y: fixed) }
            )
        }

        return segments
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

    // MARK: - Stream function (orthogonal contours)

    /// Compute an approximate stream function whose isolines are perpendicular
    /// to the depth isolines. Uses row-then-column integration of the rotated gradient.
    ///
    /// Given depth field f, the stream function ψ satisfies:
    ///   ∂ψ/∂x = −∂f/∂y,  ∂ψ/∂y = ∂f/∂x
    /// so ∇ψ ⊥ ∇f and their respective isolines cross at right angles.
    private static func computeStreamFunction(
        vertices: [Double],
        vertW: Int, vertH: Int,
        backgroundCutoff: Double
    ) -> [Double] {
        var psi = [Double](repeating: 0, count: vertW * vertH)

        // Integrate along the first row using ∂ψ/∂x = −∂f/∂y
        // We approximate ∂f/∂y with a forward difference clipped at the boundary.
        for j in 1..<vertW {
            let fy: Double
            if vertH > 1 {
                fy = vertices[1 * vertW + (j - 1)] - vertices[0 * vertW + (j - 1)]
            } else {
                fy = 0
            }
            psi[j] = psi[j - 1] + (-fy)
        }

        // For each subsequent row, integrate down using ∂ψ/∂y = ∂f/∂x
        for i in 1..<vertH {
            for j in 0..<vertW {
                let fx: Double
                if j < vertW - 1 {
                    fx = vertices[(i - 1) * vertW + j + 1] - vertices[(i - 1) * vertW + j]
                } else {
                    fx = vertices[(i - 1) * vertW + j] - vertices[(i - 1) * vertW + j - 1]
                }
                psi[i * vertW + j] = psi[(i - 1) * vertW + j] + fx
            }
        }

        return psi
    }

    /// Compute evenly-spaced thresholds for the stream function field,
    /// considering only vertices in the non-background region.
    private static func computeOrthogonalThresholds(
        field: [Double],
        backgroundMask: [Double],
        backgroundCutoff: Double,
        levels: Int
    ) -> [Double] {
        // Find the range of ψ within the foreground region
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for i in field.indices {
            guard backgroundMask[i] < backgroundCutoff else { continue }
            lo = min(lo, field[i])
            hi = max(hi, field[i])
        }
        guard hi > lo, levels > 0 else { return [] }

        var thresholds: [Double] = []
        thresholds.reserveCapacity(levels)
        for i in 0..<levels {
            thresholds.append(lo + (hi - lo) * Double(i + 1) / Double(levels + 1))
        }
        return thresholds
    }

    // MARK: - Projected grid tracing

    private static func appendProjectedPolyline(
        segments: inout [GridLineSegment],
        vertices: [Double],
        sampleCount: Int,
        sampleSteps: Int,
        backgroundCutoff: Double,
        depthLowerBound: Double,
        visibleDepthRange: Double,
        camera: ProjectedGridCamera,
        pointAt: (Double) -> CGPoint
    ) {
        var previousBase = pointAt(0)
        var previousDepth = sampleField(vertices, sampleCount: sampleCount, at: previousBase)
        var previousVisible = previousDepth < backgroundCutoff
        var previousProjected = projectedPoint(
            basePoint: previousBase,
            depth: previousDepth,
            backgroundCutoff: backgroundCutoff,
            depthLowerBound: depthLowerBound,
            visibleDepthRange: visibleDepthRange,
            camera: camera
        )

        for step in 1...sampleSteps {
            let t = Double(step) / Double(sampleSteps)
            let base = pointAt(t)
            let depth = sampleField(vertices, sampleCount: sampleCount, at: base)
            let visible = depth < backgroundCutoff
            let projected = projectedPoint(
                basePoint: base,
                depth: depth,
                backgroundCutoff: backgroundCutoff,
                depthLowerBound: depthLowerBound,
                visibleDepthRange: visibleDepthRange,
                camera: camera
            )

            switch (previousVisible, visible) {
            case (true, true):
                appendSegment(
                    &segments,
                    start: previousProjected,
                    end: projected
                )
            case (true, false):
                let crossing = backgroundCrossingPoint(
                    fromPoint: previousBase,
                    fromDepth: previousDepth,
                    toPoint: base,
                    toDepth: depth,
                    backgroundCutoff: backgroundCutoff
                )
                appendSegment(
                    &segments,
                    start: previousProjected,
                    end: crossing
                )
            case (false, true):
                let crossing = backgroundCrossingPoint(
                    fromPoint: previousBase,
                    fromDepth: previousDepth,
                    toPoint: base,
                    toDepth: depth,
                    backgroundCutoff: backgroundCutoff
                )
                appendSegment(
                    &segments,
                    start: crossing,
                    end: projected
                )
            case (false, false):
                break
            }

            previousBase = base
            previousDepth = depth
            previousVisible = visible
            previousProjected = projected
        }
    }

    private static func appendSegment(
        _ segments: inout [GridLineSegment],
        start: CGPoint,
        end: CGPoint
    ) {
        let segment = GridLineSegment(
            start: CGPoint(
                x: max(0, min(1, start.x)),
                y: max(0, min(1, start.y))
            ),
            end: CGPoint(
                x: max(0, min(1, end.x)),
                y: max(0, min(1, end.y))
            )
        )
        if !segment.isDegenerate {
            segments.append(segment)
        }
    }

    private static func projectedPoint(
        basePoint: CGPoint,
        depth: Double,
        backgroundCutoff: Double,
        depthLowerBound: Double,
        visibleDepthRange: Double,
        camera: ProjectedGridCamera
    ) -> CGPoint {
        let relief = max(0, min(1, (backgroundCutoff - depth) / visibleDepthRange))
        return camera.project(basePoint: basePoint, relief: relief)
    }

    private static func backgroundCrossingPoint(
        fromPoint: CGPoint,
        fromDepth: Double,
        toPoint: CGPoint,
        toDepth: Double,
        backgroundCutoff: Double
    ) -> CGPoint {
        let t = safeLerp(backgroundCutoff, fromDepth, toDepth)
        return CGPoint(
            x: fromPoint.x + (toPoint.x - fromPoint.x) * t,
            y: fromPoint.y + (toPoint.y - fromPoint.y) * t
        )
    }

    private static func sampleField(
        _ vertices: [Double],
        sampleCount: Int,
        at point: CGPoint
    ) -> Double {
        let maxCoord = Double(sampleCount - 1)
        let x = max(0, min(maxCoord, point.x * maxCoord))
        let y = max(0, min(maxCoord, point.y * maxCoord))
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(sampleCount - 1, x0 + 1)
        let y1 = min(sampleCount - 1, y0 + 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)

        let tl = vertices[y0 * sampleCount + x0]
        let tr = vertices[y0 * sampleCount + x1]
        let bl = vertices[y1 * sampleCount + x0]
        let br = vertices[y1 * sampleCount + x1]

        let top = tl + (tr - tl) * tx
        let bottom = bl + (br - bl) * tx
        return top + (bottom - top) * ty
    }

    private struct ProjectedGridCamera {
        let depthScale: Double
        let focalLength: Double
        let cameraDistance: Double
        let cosPitch: Double
        let sinPitch: Double
        let cosYaw: Double
        let sinYaw: Double

        init(depthScale: Double) {
            self.depthScale = depthScale
            focalLength = 2.0
            cameraDistance = 2.4 + depthScale * 1.2

            let pitch = -0.7
            let yaw = 0.55
            cosPitch = cos(pitch)
            sinPitch = sin(pitch)
            cosYaw = cos(yaw)
            sinYaw = sin(yaw)
        }

        func project(basePoint: CGPoint, relief: Double) -> CGPoint {
            let x = Double(basePoint.x) - 0.5
            let y = Double(basePoint.y) - 0.5
            let z = relief * depthScale

            let yawedX = cosYaw * x + sinYaw * z
            let yawedZ = -sinYaw * x + cosYaw * z
            let pitchedY = cosPitch * y - sinPitch * yawedZ
            let pitchedZ = sinPitch * y + cosPitch * yawedZ

            let denominator = max(0.2, cameraDistance - pitchedZ)
            let scale = focalLength / denominator

            return CGPoint(
                x: 0.5 + yawedX * scale,
                y: 0.5 + pitchedY * scale
            )
        }
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
