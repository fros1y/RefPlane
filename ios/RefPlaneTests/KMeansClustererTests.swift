import Testing
@testable import Underpaint

// MARK: - KMeansClusterer
//
// Note: forgyInit uses Int.random() internally and is not seedable.
// Tests focus on structural invariants and deterministic edge cases.

@Test
func clusterEmptyInputReturnsEmpty() {
    let result = KMeansClusterer.cluster(points: [], k: 3)
    #expect(result.centroids.isEmpty)
    #expect(result.assignments.isEmpty)
}

@Test
func clusterKZeroReturnsEmpty() {
    let point = OklabColor(L: 0.5, a: 0.1, b: 0.0)
    let result = KMeansClusterer.cluster(points: [point], k: 0)
    #expect(result.centroids.isEmpty)
    #expect(result.assignments.isEmpty)
}

@Test
func clusterAssignmentsCountMatchesPoints() {
    let points = (0..<20).map { i in
        OklabColor(L: Float(i) / 20.0, a: 0.0, b: 0.0)
    }
    let result = KMeansClusterer.cluster(points: points, k: 4)
    #expect(result.assignments.count == points.count)
}

@Test
func clusterAssignmentsAreValidIndices() {
    let points = (0..<30).map { i in
        OklabColor(L: Float(i) / 30.0, a: Float(i % 5) * 0.05, b: 0.0)
    }
    let result = KMeansClusterer.cluster(points: points, k: 5)
    for assignment in result.assignments {
        #expect(assignment >= 0 && assignment < result.centroids.count)
    }
}

@Test
func clusterKExceedingPointCountClamped() {
    // k is clamped to min(k, points.count) — so at most 2 centroids for 2 points
    let p1 = OklabColor(L: 0.2, a: 0.1, b: 0.0)
    let p2 = OklabColor(L: 0.8, a: -0.1, b: 0.0)
    let result = KMeansClusterer.cluster(points: [p1, p2], k: 10)
    #expect(result.centroids.count <= 2)
    #expect(result.assignments.count == 2)
}

@Test
func clusterIdenticalPointsConverges() {
    // All points identical → all centroids converge to the same location,
    // all assignments point to centroid index 0 (closest due to tie-breaking).
    let point = OklabColor(L: 0.5, a: 0.12, b: -0.08)
    let points = [OklabColor](repeating: point, count: 50)
    let result = KMeansClusterer.cluster(points: points, k: 3)

    // All centroids must equal the repeated point (within float tolerance)
    for centroid in result.centroids {
        #expect(abs(centroid.L - point.L) < 1e-4)
        #expect(abs(centroid.a - point.a) < 1e-4)
        #expect(abs(centroid.b - point.b) < 1e-4)
    }

    // All assignments must be the same (all equidistant → first wins)
    let firstAssignment = result.assignments[0]
    #expect(result.assignments.allSatisfy { $0 == firstAssignment })
}

@Test
func clusterCentroidsWithinInputRange() {
    // Invariant: each centroid's L/a/b must lie within the range of the input points.
    for seed in 1...50 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let n = generator.int(in: 5...30)
        let k = generator.int(in: 1...4)
        let points = (0..<n).map { _ in
            OklabColor(
                L: Float(generator.double(in: 0.0...1.0)),
                a: Float(generator.double(in: -0.4...0.4)),
                b: Float(generator.double(in: -0.4...0.4))
            )
        }

        let result = KMeansClusterer.cluster(points: points, k: k)

        let minL = points.map(\.L).min()!
        let maxL = points.map(\.L).max()!
        let minA = points.map(\.a).min()!
        let maxA = points.map(\.a).max()!
        let minB = points.map(\.b).min()!
        let maxB = points.map(\.b).max()!

        for centroid in result.centroids {
            #expect(centroid.L >= minL - 1e-4 && centroid.L <= maxL + 1e-4)
            #expect(centroid.a >= minA - 1e-4 && centroid.a <= maxA + 1e-4)
            #expect(centroid.b >= minB - 1e-4 && centroid.b <= maxB + 1e-4)
        }
    }
}

@Test
func forgyInitReturnsCentroidsFromInputPoints() {
    let points = (0..<10).map { i in
        OklabColor(L: Float(i) * 0.1, a: Float(i) * 0.02, b: 0.0)
    }
    let centroids = KMeansClusterer.forgyInit(points: points, k: 3)
    #expect(centroids.count == 3)
    // Every returned centroid must equal one of the input points (within float precision)
    for centroid in centroids {
        let matchesInput = points.contains { p in
            abs(p.L - centroid.L) < 1e-6 &&
            abs(p.a - centroid.a) < 1e-6 &&
            abs(p.b - centroid.b) < 1e-6
        }
        #expect(matchesInput)
    }
}
