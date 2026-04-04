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
        smoothContours: Bool = true
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
            backgroundCutoff: backgroundCutoff,
            smoothContours: smoothContours
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
        backgroundCutoff: Double,
        smoothContours: Bool
    ) -> [GridLineSegment] {
        var segments: [GridLineSegment] = []
        segments.reserveCapacity(thresholds.count * gridW * 2)

        let invW = 1.0 / Double(gridW)
        let invH = 1.0 / Double(gridH)

        for threshold in thresholds {
            var levelSegments: [GridLineSegment] = []
            levelSegments.reserveCapacity(gridW * 2)

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

                    let caseIndex = (tl < threshold ? 8 : 0) |
                                    (tr < threshold ? 4 : 0) |
                                    (br < threshold ? 2 : 0) |
                                    (bl < threshold ? 1 : 0)

                    guard caseIndex != 0 && caseIndex != 15 else { continue }

                    let cellSegments = marchingSquaresSegments(
                        caseIndex: caseIndex,
                        col: col, row: row,
                        tl: tl, tr: tr, bl: bl, br: br,
                        threshold: threshold
                    )

                    for (p0, p1) in cellSegments {
                        let seg = GridLineSegment(
                            start: CGPoint(x: p0.x * invW, y: p0.y * invH),
                            end: CGPoint(x: p1.x * invW, y: p1.y * invH)
                        )
                        if !seg.isDegenerate {
                            levelSegments.append(seg)
                        }
                    }
                }
            }

            if smoothContours {
                segments.append(contentsOf: smoothSegments(levelSegments))
            } else {
                segments.append(contentsOf: levelSegments)
            }
        }

        return segments
    }

    // MARK: - Segment smoothing

    private static let smoothingSubdivisionCount = 6
    private static let endpointQuantizationScale: CGFloat = 10_000

    private struct PointKey: Hashable {
        let x: Int
        let y: Int
    }

    private static func smoothSegments(_ segments: [GridLineSegment]) -> [GridLineSegment] {
        guard segments.count > 2 else { return segments }

        var result: [GridLineSegment] = []
        result.reserveCapacity(segments.count * smoothingSubdivisionCount)

        for chain in buildPointChains(from: segments) {
            let smoothedPoints = smoothPointChain(chain.points, closed: chain.closed)
            if smoothedPoints.count < 2 {
                continue
            }

            for index in 0..<(smoothedPoints.count - 1) {
                let start = clampedPoint(smoothedPoints[index])
                let end = clampedPoint(smoothedPoints[index + 1])
                let segment = GridLineSegment(start: start, end: end)
                if !segment.isDegenerate {
                    result.append(segment)
                }
            }

            if chain.closed {
                let closing = GridLineSegment(
                    start: clampedPoint(smoothedPoints[smoothedPoints.count - 1]),
                    end: clampedPoint(smoothedPoints[0])
                )
                if !closing.isDegenerate {
                    result.append(closing)
                }
            }
        }

        return result.isEmpty ? segments : result
    }

    private static func buildPointChains(from segments: [GridLineSegment]) -> [(points: [CGPoint], closed: Bool)] {
        var endpointsBySegment: [(start: PointKey, end: PointKey)] = []
        endpointsBySegment.reserveCapacity(segments.count)

        var adjacency: [PointKey: [Int]] = [:]
        adjacency.reserveCapacity(segments.count * 2)

        for (index, segment) in segments.enumerated() {
            let startKey = pointKey(segment.start)
            let endKey = pointKey(segment.end)
            endpointsBySegment.append((start: startKey, end: endKey))
            adjacency[startKey, default: []].append(index)
            adjacency[endKey, default: []].append(index)
        }

        var visited = [Bool](repeating: false, count: segments.count)
        var chains: [(points: [CGPoint], closed: Bool)] = []
        chains.reserveCapacity(segments.count / 2)

        for index in segments.indices where !visited[index] {
            visited[index] = true

            var points = [segments[index].start, segments[index].end]
            extend(points: &points, atStart: false, segments: segments, endpointsBySegment: endpointsBySegment, adjacency: adjacency, visited: &visited)
            extend(points: &points, atStart: true, segments: segments, endpointsBySegment: endpointsBySegment, adjacency: adjacency, visited: &visited)

            if points.count < 2 {
                continue
            }

            let closed = pointKey(points.first!) == pointKey(points.last!)
            if closed {
                points.removeLast()
            }

            chains.append((points: dedupedAdjacentPoints(points), closed: closed))
        }

        return chains
    }

    private static func extend(
        points: inout [CGPoint],
        atStart: Bool,
        segments: [GridLineSegment],
        endpointsBySegment: [(start: PointKey, end: PointKey)],
        adjacency: [PointKey: [Int]],
        visited: inout [Bool]
    ) {
        while true {
            guard let currentPoint = atStart ? points.first : points.last else { return }
            let currentKey = pointKey(currentPoint)
            guard let candidates = adjacency[currentKey] else { return }

            var nextIndex: Int?
            for candidate in candidates where !visited[candidate] {
                nextIndex = candidate
                break
            }

            guard let segmentIndex = nextIndex else { return }
            visited[segmentIndex] = true

            let segment = segments[segmentIndex]
            let endpoints = endpointsBySegment[segmentIndex]
            let nextPoint: CGPoint

            if endpoints.start == currentKey {
                nextPoint = segment.end
            } else {
                nextPoint = segment.start
            }

            if atStart {
                points.insert(nextPoint, at: 0)
            } else {
                points.append(nextPoint)
            }
        }
    }

    private static func smoothPointChain(_ points: [CGPoint], closed: Bool) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        if points.count == 2 {
            return points
        }

        var output: [CGPoint] = [points[0]]
        let count = points.count
        let segmentCount = closed ? count : (count - 1)

        for index in 0..<segmentCount {
            let p0 = controlPoint(before: index, points: points, closed: closed)
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = controlPoint(after: index + 1, points: points, closed: closed)

            for step in 1...smoothingSubdivisionCount {
                let t = CGFloat(step) / CGFloat(smoothingSubdivisionCount)
                output.append(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: t))
            }
        }

        if closed, pointKey(output[0]) == pointKey(output[output.count - 1]) {
            output.removeLast()
        }

        return dedupedAdjacentPoints(output)
    }

    private static func controlPoint(before index: Int, points: [CGPoint], closed: Bool) -> CGPoint {
        if closed {
            let wrapped = (index - 1 + points.count) % points.count
            return points[wrapped]
        }
        if index > 0 {
            return points[index - 1]
        }
        return reflectedAnchor(anchor: points[0], neighbor: points[1])
    }

    private static func controlPoint(after index: Int, points: [CGPoint], closed: Bool) -> CGPoint {
        if closed {
            let wrapped = (index + 1) % points.count
            return points[wrapped]
        }
        if index + 1 < points.count {
            return points[index + 1]
        }
        return reflectedAnchor(anchor: points[points.count - 1], neighbor: points[points.count - 2])
    }

    private static func reflectedAnchor(anchor: CGPoint, neighbor: CGPoint) -> CGPoint {
        CGPoint(
            x: anchor.x + (anchor.x - neighbor.x),
            y: anchor.y + (anchor.y - neighbor.y)
        )
    }

    private static func catmullRom(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t

        let x = 0.5 * (
            (2 * p1.x) +
            (-p0.x + p2.x) * t +
            (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
            (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3
        )

        let y = 0.5 * (
            (2 * p1.y) +
            (-p0.y + p2.y) * t +
            (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
            (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3
        )

        return CGPoint(x: x, y: y)
    }

    private static func pointKey(_ point: CGPoint) -> PointKey {
        PointKey(
            x: Int((point.x * endpointQuantizationScale).rounded()),
            y: Int((point.y * endpointQuantizationScale).rounded())
        )
    }

    private static func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(1, max(0, point.x)),
            y: min(1, max(0, point.y))
        )
    }

    private static func dedupedAdjacentPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var deduped: [CGPoint] = [last]
        deduped.reserveCapacity(points.count)

        for point in points.dropFirst() {
            if pointKey(point) != pointKey(last) {
                deduped.append(point)
                last = point
            }
        }

        return deduped
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
