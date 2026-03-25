import Foundation

// MARK: - K-Means++ clustering in Oklab space

struct KMeansResult {
    let centroids: [OklabColor]
    let assignments: [Int]  // index per pixel
}

enum KMeansClusterer {

    /// Cluster `points` into `k` groups using k-means++ init + 20 iterations.
    /// `lWeight` de-emphasizes luminance for chroma-focused clustering.
    static func cluster(points: [OklabColor], k: Int, lWeight: Float = 0.1) -> KMeansResult {
        guard !points.isEmpty, k > 0 else {
            return KMeansResult(centroids: [], assignments: [])
        }
        let k = min(k, points.count)

        var centroids = kMeansPlusPlusInit(points: points, k: k, lWeight: lWeight)
        var assignments = [Int](repeating: 0, count: points.count)

        for _ in 0..<20 {
            // Assignment step
            var changed = false
            for i in 0..<points.count {
                var bestIdx = 0
                var bestDist = Float.greatestFiniteMagnitude
                for c in 0..<centroids.count {
                    let d = oklabDistanceColorWeighted(points[i], centroids[c], lWeight: lWeight)
                    if d < bestDist { bestDist = d; bestIdx = c }
                }
                if assignments[i] != bestIdx { changed = true; assignments[i] = bestIdx }
            }

            // Update step
            var sums = [(L: Float, a: Float, b: Float, count: Int)](
                repeating: (0, 0, 0, 0), count: centroids.count)
            for i in 0..<points.count {
                let c = assignments[i]
                sums[c].L += points[i].L
                sums[c].a += points[i].a
                sums[c].b += points[i].b
                sums[c].count += 1
            }

            var maxShift: Float = 0
            for c in 0..<centroids.count {
                if sums[c].count > 0 {
                    let n = Float(sums[c].count)
                    let newC = OklabColor(L: sums[c].L / n, a: sums[c].a / n, b: sums[c].b / n)
                    let shift = oklabDistance(centroids[c], newC)
                    if shift > maxShift { maxShift = shift }
                    centroids[c] = newC
                }
            }

            if !changed || maxShift < 0.001 { break }
        }

        return KMeansResult(centroids: centroids, assignments: assignments)
    }

    // MARK: - K-Means++ initialization (exposed for GPU hybrid path)

    static func kMeansPlusPlusInit(points: [OklabColor], k: Int, lWeight: Float) -> [OklabColor] {
        var centroids: [OklabColor] = []
        // Pick first centroid randomly
        centroids.append(points[Int.random(in: 0..<points.count)])

        for _ in 1..<k {
            // Compute D²(x) for each point
            var distances = [Float](repeating: 0, count: points.count)
            var total: Float = 0
            for i in 0..<points.count {
                var minDist = Float.greatestFiniteMagnitude
                for c in centroids {
                    let d = oklabDistanceColorWeighted(points[i], c, lWeight: lWeight)
                    if d < minDist { minDist = d }
                }
                distances[i] = minDist
                total += minDist
            }

            // If all points are identical (total == 0), fall back to a random pick
            guard total > 0 else {
                centroids.append(points[Int.random(in: 0..<points.count)])
                continue
            }

            // Choose next centroid proportional to D²
            var threshold = Float.random(in: 0..<total)
            var chosen = points.count - 1
            for i in 0..<points.count {
                threshold -= distances[i]
                if threshold <= 0 { chosen = i; break }
            }
            centroids.append(points[chosen])
        }
        return centroids
    }
}
