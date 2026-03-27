import Testing
@testable import Underpaint

// MARK: - RegionCleaner
//
// minPixels = Int(Double(width * height) * minFactor)
// A region is cleaned when regionCount < minPixels.
//
// Implementation note: labels are mutated in-place during a single scan.
// A pixel's label can change AFTER it has been marked visited, which means
// one pass does not guarantee every region ends up >= minPixels.
// Tests below verify correct local behaviour and structural invariants
// rather than global convergence properties.

@Test
func cleanUniformGridIsUnchanged() {
    // 4×4, all label 0. One component of 16 pixels; minPixels=3. 16 >= 3 → unchanged.
    var labels = [Int32](repeating: 0, count: 16)
    let original = labels
    RegionCleaner.clean(labels: &labels, width: 4, height: 4, minFactor: 0.2)
    #expect(labels == original)
}

@Test
func cleanSingleIsolatedPixelMerged() {
    // 10×1 grid: first 9 pixels are label 0, last pixel is label 1.
    // minFactor=0.2 → minPixels=2. Region of label 1 (size 1) < 2 → merged to label 0.
    var labels: [Int32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    RegionCleaner.clean(labels: &labels, width: 10, height: 1, minFactor: 0.2)
    #expect(labels.allSatisfy { $0 == 0 })
}

@Test
func cleanLargeRegionPreserved() {
    // 10×1 grid: 5 pixels label 0, 5 pixels label 1.
    // minFactor=0.2 → minPixels=2. Both regions ≥ 2 → unchanged.
    var labels: [Int32] = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
    let original = labels
    RegionCleaner.clean(labels: &labels, width: 10, height: 1, minFactor: 0.2)
    #expect(labels == original)
}

@Test
func cleanReplacesWithDominantNeighbor() {
    // 3×3 grid:
    //   0 0 0
    //   2 1 2   ← center pixel (label 1) has 3 label-2 neighbors and 1 label-0 neighbor
    //   2 2 2
    // minFactor=0.25 → minPixels=2. Region label 1 (size 1) < 2 → replaced by dominant (label 2).
    var labels: [Int32] = [
        0, 0, 0,
        2, 1, 2,
        2, 2, 2,
    ]
    RegionCleaner.clean(labels: &labels, width: 3, height: 3, minFactor: 0.25)
    #expect(labels[4] == 2)  // center pixel replaced by dominant neighbor (label 2)
    // Surrounding pixels unchanged
    #expect(labels[0] == 0)
    #expect(labels[1] == 0)
    #expect(labels[2] == 0)
}

@Test
func cleanMultipleSmallRegionsSurroundedBySameLabelAbsorbed() {
    // 10×1 grid: two isolated pixels (labels 1 and 2) surrounded on both sides by label 0.
    // Each small pixel's only neighbors are label 0, so both merge cleanly into label 0.
    // minFactor=0.2 → minPixels=2.
    var labels: [Int32] = [0, 0, 0, 1, 0, 0, 0, 2, 0, 0]
    RegionCleaner.clean(labels: &labels, width: 10, height: 1, minFactor: 0.2)
    #expect(labels.allSatisfy { $0 == 0 })
}

@Test
func cleanWithZeroMinFactorDoesNothing() {
    // minFactor=0.0 → minPixels=0 → guard returns early, no changes.
    var labels: [Int32] = [0, 1, 0, 1, 0]
    let original = labels
    RegionCleaner.clean(labels: &labels, width: 5, height: 1, minFactor: 0.0)
    #expect(labels == original)
}

@Test
func cleanPreservesExistingLabelsOnly() {
    // After cleaning, all output labels must be a subset of the input labels.
    for seed in 1...100 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let width = 8
        let height = 8
        let total = width * height
        var labels = (0..<total).map { _ in Int32(generator.int(in: 0...3)) }
        let inputLabels = Set(labels)

        RegionCleaner.clean(labels: &labels, width: width, height: height, minFactor: 0.1)

        let outputLabels = Set(labels)
        #expect(outputLabels.isSubset(of: inputLabels))
    }
}

@Test
func cleanLargeRegionsRemainUnmodified() {
    // Pixels belonging to regions that are already >= minPixels must never be relabeled.
    // The algorithm only mutates pixels in small regions; large-region pixels are read-only.
    //
    // Layout (9×1): [0,0,0 | 1 | 2,2,2,2,2]
    //   Region label 0 (size 3) ≥ minPixels=2 → labels 0–2 stay 0
    //   Region label 1 (size 1) < 2 → merged to its dominant neighbor
    //   Region label 2 (size 5) ≥ 2 → labels 4–8 stay 2
    var labels: [Int32] = [0, 0, 0, 1, 2, 2, 2, 2, 2]
    RegionCleaner.clean(labels: &labels, width: 9, height: 1, minFactor: 0.25)

    // Large-region pixels must be unchanged
    #expect(labels[0] == 0)
    #expect(labels[1] == 0)
    #expect(labels[2] == 0)
    #expect(labels[4] == 2)
    #expect(labels[5] == 2)
    #expect(labels[6] == 2)
    #expect(labels[7] == 2)
    #expect(labels[8] == 2)

    // Small pixel (label 1) must have been absorbed into one of its neighbors
    #expect(labels[3] == 0 || labels[3] == 2)
}
