import Foundation

// MARK: - BFS flood-fill region cleanup (optimized)

enum RegionCleaner {

    /// Replace small regions (< threshold pixels) with a neighboring different color.
    /// - Parameters:
    ///   - labels: flat array of label indices (width × height)
    ///   - width/height: image dimensions
    ///   - minFactor: fraction of total pixels; regions below this are merged
    /// Optimized: pre-allocated queue, inline neighbor checks, batch processing
    static func clean(labels: inout [Int32], width: Int, height: Int, minFactor: Double) {
        let total = width * height
        let minPixels = Int(Double(total) * minFactor)
        guard minPixels > 0 else { return }

        var visited = [Bool](repeating: false, count: total)
        // Pre-allocate queue once for all BFS traversals (reuse buffer)
        var queue = [Int](repeating: 0, count: total)
        var region = [Int](repeating: 0, count: total)

        for startIdx in 0..<total {
            guard !visited[startIdx] else { continue }

            let label = labels[startIdx]
            // BFS with reusable pre-allocated arrays
            queue[0] = startIdx
            visited[startIdx] = true
            var regionCount = 0
            var head = 0
            var queueEnd = 1

            while head < queueEnd {
                let idx = queue[head]
                head += 1
                region[regionCount] = idx
                regionCount += 1

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
                // Find most common neighboring label (different from own)
                var neighborCounts = [Int32: Int]()
                for i in 0..<regionCount {
                    let idx = region[i]
                    let x = idx % width
                    let y = idx / width

                    // Check 4 neighbors
                    if x > 0 {
                        let nl = labels[idx - 1]
                        if nl != label { neighborCounts[nl, default: 0] += 1 }
                    }
                    if x < width - 1 {
                        let nl = labels[idx + 1]
                        if nl != label { neighborCounts[nl, default: 0] += 1 }
                    }
                    if y > 0 {
                        let nl = labels[idx - width]
                        if nl != label { neighborCounts[nl, default: 0] += 1 }
                    }
                    if y < height - 1 {
                        let nl = labels[idx + width]
                        if nl != label { neighborCounts[nl, default: 0] += 1 }
                    }
                }

                if let replacement = neighborCounts.max(by: { $0.value < $1.value })?.key {
                    for i in 0..<regionCount {
                        labels[region[i]] = replacement
                    }
                }
            }
        }
    }
}
