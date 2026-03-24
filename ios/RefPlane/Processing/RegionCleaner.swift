import Foundation

// MARK: - BFS flood-fill region cleanup

enum RegionCleaner {

    /// Replace small regions (< threshold pixels) with a neighboring different color.
    /// - Parameters:
    ///   - labels: flat array of label indices (width × height)
    ///   - width/height: image dimensions
    ///   - minFactor: fraction of total pixels; regions below this are merged
    static func clean(labels: inout [Int32], width: Int, height: Int, minFactor: Double) {
        let total = width * height
        let minPixels = Int(Double(total) * minFactor)
        guard minPixels > 0 else { return }

        var visited = [Bool](repeating: false, count: total)

        for startIdx in 0..<total {
            guard !visited[startIdx] else { continue }

            let label = labels[startIdx]
            // BFS
            var queue = [Int]()
            queue.reserveCapacity(256)
            queue.append(startIdx)
            visited[startIdx] = true
            var region = [Int]()
            region.reserveCapacity(256)

            var head = 0
            while head < queue.count {
                let idx = queue[head]; head += 1
                region.append(idx)
                let x = idx % width
                let y = idx / width
                // 4-connected neighbors
                let neighbors = [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]
                for (nx, ny) in neighbors {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let ni = ny * width + nx
                    guard !visited[ni], labels[ni] == label else { continue }
                    visited[ni] = true
                    queue.append(ni)
                }
            }

            if region.count < minPixels {
                // Find most common neighboring label (different from own)
                var neighborCounts = [Int32: Int]()
                for idx in region {
                    let x = idx % width
                    let y = idx / width
                    for (nx, ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] {
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let ni = ny * width + nx
                        let nl = labels[ni]
                        if nl != label {
                            neighborCounts[nl, default: 0] += 1
                        }
                    }
                }
                if let replacement = neighborCounts.max(by: { $0.value < $1.value })?.key {
                    for idx in region {
                        labels[idx] = replacement
                    }
                }
            }
        }
    }
}
