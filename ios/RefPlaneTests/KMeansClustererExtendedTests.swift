import Testing
@testable import Underpaint

// MARK: - KMeansClusterer extended tests

@Test
func kMeansPlusPlusInitReturnsKCentroids() {
    let points = [
        OklabColor(L: 0.1, a: 0.0, b: 0.0),
        OklabColor(L: 0.3, a: 0.0, b: 0.0),
        OklabColor(L: 0.5, a: 0.0, b: 0.0),
        OklabColor(L: 0.7, a: 0.0, b: 0.0),
        OklabColor(L: 0.9, a: 0.0, b: 0.0),
    ]
    let centroids = KMeansClusterer.kMeansPlusPlusInit(points: points, k: 3, lWeight: 0.3)
    #expect(centroids.count == 3)
}

@Test
func kMeansPlusPlusInitWithIdenticalPoints() {
    let point = OklabColor(L: 0.5, a: 0.1, b: -0.1)
    let points = [OklabColor](repeating: point, count: 10)
    let centroids = KMeansClusterer.kMeansPlusPlusInit(points: points, k: 3, lWeight: 0.3)
    #expect(centroids.count == 3)
    // All centroids should be the same point since all inputs are identical
    for c in centroids {
        #expect(abs(c.L - 0.5) < 0.001)
    }
}

@Test
func forgyInitReturnsKCentroids() {
    let points = (0..<20).map { i in
        OklabColor(L: Float(i) / 20.0, a: 0, b: 0)
    }
    let centroids = KMeansClusterer.forgyInit(points: points, k: 5)
    #expect(centroids.count == 5)
}

@Test
func forgyInitCentroidsAreFromPoints() {
    let points = [
        OklabColor(L: 0.1, a: 0.2, b: 0.3),
        OklabColor(L: 0.4, a: 0.5, b: 0.6),
        OklabColor(L: 0.7, a: 0.8, b: 0.9),
    ]
    let centroids = KMeansClusterer.forgyInit(points: points, k: 2)
    // All centroids should be actual points from the input
    for c in centroids {
        let isFromInput = points.contains(where: {
            abs($0.L - c.L) < 0.001 && abs($0.a - c.a) < 0.001 && abs($0.b - c.b) < 0.001
        })
        #expect(isFromInput)
    }
}

@Test
func clusterWithEmptyPoints() {
    let result = KMeansClusterer.cluster(points: [], k: 3)
    #expect(result.centroids.isEmpty)
    #expect(result.assignments.isEmpty)
}

@Test
func clusterWithZeroK() {
    let points = [OklabColor(L: 0.5, a: 0, b: 0)]
    let result = KMeansClusterer.cluster(points: points, k: 0)
    #expect(result.centroids.isEmpty)
}

@Test
func clusterKLargerThanPointsClamps() {
    let points = [
        OklabColor(L: 0.2, a: 0, b: 0),
        OklabColor(L: 0.8, a: 0, b: 0),
    ]
    // k=5 but only 2 points, should clamp to k=2
    let result = KMeansClusterer.cluster(points: points, k: 5)
    #expect(result.centroids.count == 2)
    #expect(result.assignments.count == 2)
}

@Test
func clusterAssignmentsAreInRange() {
    let points = (0..<50).map { i in
        OklabColor(L: Float(i) / 50.0, a: Float.random(in: -0.1...0.1), b: Float.random(in: -0.1...0.1))
    }
    let result = KMeansClusterer.cluster(points: points, k: 5, lWeight: 0.3)
    #expect(result.assignments.count == 50)
    for assignment in result.assignments {
        #expect(assignment >= 0)
        #expect(assignment < result.centroids.count)
    }
}

@Test
func clusterWellSeparatedPointsConverges() {
    // Three clearly separated clusters
    var points = [OklabColor]()
    for _ in 0..<20 { points.append(OklabColor(L: 0.1, a: -0.3, b: 0.0)) }
    for _ in 0..<20 { points.append(OklabColor(L: 0.5, a: 0.0, b: 0.3)) }
    for _ in 0..<20 { points.append(OklabColor(L: 0.9, a: 0.3, b: 0.0)) }

    let result = KMeansClusterer.cluster(points: points, k: 3, lWeight: 0.3)
    #expect(result.centroids.count == 3)

    // Each point in the first group should have the same assignment
    let firstGroupAssignment = result.assignments[0]
    for i in 0..<20 {
        #expect(result.assignments[i] == firstGroupAssignment)
    }
}
