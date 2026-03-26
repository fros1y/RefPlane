import Foundation

// MARK: - BFS flood-fill region cleanup (optimized)

enum RegionCleaner {

    /// Replace small regions (< threshold pixels) with a neighboring different color.
    /// - Parameters:
    ///   - labels: flat array of label indices (width × height)
    ///   - width/height: image dimensions
    ///   - minFactor: fraction of total pixels; regions below this are merged
    /// Optimized: pre-allocated queue, inline neighbor checks, batch processing
    static func clean(
        labels: inout [Int32],
        width: Int,
        height: Int,
        minFactor: Double,
        labelCapacity: Int
    ) {
        let total = width * height
        let minPixels = Int(Double(total) * minFactor)
        guard minPixels > 0, labelCapacity > 0 else { return }

        var visited = [Bool](repeating: false, count: total)
        // Pre-allocate queue once for all BFS traversals (reuse buffer)
        var queue = [Int](repeating: 0, count: total)
        var region = [Int](repeating: 0, count: total)
        var neighborCounts = [Int](repeating: 0, count: labelCapacity)
        var touchedLabels = [Int](repeating: 0, count: labelCapacity)

        for startIdx in 0..<total {
            guard !visited[startIdx] else { continue }

            let label = labels[startIdx]
            queue[0] = startIdx
            visited[startIdx] = true
            var regionCount = 0
            var storedCount = 0
            var head = 0
            var queueEnd = 1

            while head < queueEnd {
                let idx = queue[head]
                head += 1
                regionCount += 1

                if storedCount < minPixels {
                    region[storedCount] = idx
                    storedCount += 1
                }

                let x = idx % width
                let y = idx / width

                // Inline 4-connected neighbor checks (unrolled loop for speed)
                // Left neighbor
                if x > 0 {
                    let ni = idx - 1
                    if !visited[ni] && labels[ni] == label {
                        visited[ni] = true
                        queue[queueEnd] = ni
                        queueEnd += 1
                    }
                }
                // Right neighbor
                if x < width - 1 {
                    let ni = idx + 1
                    if !visited[ni] && labels[ni] == label {
                        visited[ni] = true
                        queue[queueEnd] = ni
                        queueEnd += 1
                    }
                }
                // Top neighbor
                if y > 0 {
                    let ni = idx - width
                    if !visited[ni] && labels[ni] == label {
                        visited[ni] = true
                        queue[queueEnd] = ni
                        queueEnd += 1
                    }
                }
                // Bottom neighbor
                if y < height - 1 {
                    let ni = idx + width
                    if !visited[ni] && labels[ni] == label {
                        visited[ni] = true
                        queue[queueEnd] = ni
                        queueEnd += 1
                    }
                }
            }

            if regionCount < minPixels {
                var touchedCount = 0
                for i in 0..<storedCount {
                    let idx = region[i]
                    let x = idx % width
                    let y = idx / width

                    if x > 0 {
                        recordNeighbor(
                            labels[idx - 1],
                            originalLabel: label,
                            counts: &neighborCounts,
                            touchedLabels: &touchedLabels,
                            touchedCount: &touchedCount
                        )
                    }
                    if x < width - 1 {
                        recordNeighbor(
                            labels[idx + 1],
                            originalLabel: label,
                            counts: &neighborCounts,
                            touchedLabels: &touchedLabels,
                            touchedCount: &touchedCount
                        )
                    }
                    if y > 0 {
                        recordNeighbor(
                            labels[idx - width],
                            originalLabel: label,
                            counts: &neighborCounts,
                            touchedLabels: &touchedLabels,
                            touchedCount: &touchedCount
                        )
                    }
                    if y < height - 1 {
                        recordNeighbor(
                            labels[idx + width],
                            originalLabel: label,
                            counts: &neighborCounts,
                            touchedLabels: &touchedLabels,
                            touchedCount: &touchedCount
                        )
                    }
                }

                if let replacement = dominantNeighbor(
                    counts: neighborCounts,
                    touchedLabels: touchedLabels,
                    touchedCount: touchedCount
                ) {
                    for i in 0..<storedCount {
                        labels[region[i]] = Int32(replacement)
                    }
                }

                for i in 0..<touchedCount {
                    neighborCounts[touchedLabels[i]] = 0
                }
            }
        }
    }

    @inline(__always)
    private static func recordNeighbor(
        _ neighborLabel: Int32,
        originalLabel: Int32,
        counts: inout [Int],
        touchedLabels: inout [Int],
        touchedCount: inout Int
    ) {
        guard neighborLabel != originalLabel else { return }
        let index = Int(neighborLabel)
        guard index >= 0 && index < counts.count else { return }

        if counts[index] == 0 {
            touchedLabels[touchedCount] = index
            touchedCount += 1
        }
        counts[index] += 1
    }

    private static func dominantNeighbor(
        counts: [Int],
        touchedLabels: [Int],
        touchedCount: Int
    ) -> Int? {
        var bestLabel: Int?
        var bestCount = 0

        for i in 0..<touchedCount {
            let label = touchedLabels[i]
            let count = counts[label]
            if count > bestCount {
                bestCount = count
                bestLabel = label
            }
        }

        return bestLabel
    }

    static func clean(labels: inout [Int32], width: Int, height: Int, minFactor: Double) {
        let labelCapacity = Int((labels.max() ?? 0) + 1)
        clean(
            labels: &labels,
            width: width,
            height: height,
            minFactor: minFactor,
            labelCapacity: labelCapacity
        )
    }
}
