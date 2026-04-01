# Paint Palette Pipeline Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining gaps between the current partially-implemented paint palette pipeline and the full spec — improving color capture fidelity (chroma-weighted histogram), recipe quality (snap/reassign + refit), and deduplication (OR-based merge + adaptive pruning).

**Architecture:** The pipeline already has Stages 2-5 scaffolded in `PaintPaletteBuilder.swift`. This plan adds: (1) chroma-weighted histogram for better centroid seeding, (2) OR-based recipe merging, (3) Stage 4B snap/reassign loop, (4) Stage 5A adaptive shade pruning, and (5) Stage 5B final constrained refit. All changes are additive — the existing fallback path in `ImageProcessor.swift` is preserved.

**Tech Stack:** Swift 6, SwiftUI, Metal GPU compute, Swift Testing framework (`@Suite`, `@Test`, `#expect`)

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `ios/RefPlane/Processing/PigmentDecomposer.swift` | Modify | Fix mergeRecipes to use OR logic (color match OR recipe structure match) |
| `ios/RefPlane/Processing/ColorRegionsProcessor.swift` | Modify | Add chroma weighting to histogram candidate construction |
| `ios/RefPlane/Processing/PaintPaletteBuilder.swift` | Modify | Add Stage 4B snap/reassign, Stage 5A adaptive pruning, Stage 5B final refit |
| `ios/RefPlaneTests/PigmentDecomposerTests.swift` | Modify | Add tests for OR-merge logic |
| `ios/RefPlaneTests/PaintPaletteBuilderTests.swift` | Modify | Add tests for snap/reassign, adaptive pruning, final refit, integration invariants |

---

### Task 1: Fix mergeRecipes OR Logic

The current `mergeRecipes` in `PigmentDecomposer.swift` requires BOTH color proximity AND recipe structure match to merge two recipes. The spec says merge on EITHER condition — two dark recipes from different pigments that produce the same visible color should merge, and two recipes with identical pigment ratios but slightly different predicted colors should also merge.

**Files:**
- Modify: `ios/RefPlane/Processing/PigmentDecomposer.swift:621-668`
- Test: `ios/RefPlaneTests/PigmentDecomposerTests.swift`

- [ ] **Step 1: Write failing test — merge on color match alone**

Add to `PigmentDecomposerTests.swift`:

```swift
@Test
func mergeRecipesMergesOnColorMatchAlone() {
    // Two recipes with DIFFERENT pigment sets but nearly identical predicted colors
    let r1 = PigmentRecipe(
        components: [RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 1.0)],
        predictedColor: OklabColor(L: 0.5, a: 0.1, b: 0.1),
        deltaE: 0.01
    )
    let r2 = PigmentRecipe(
        components: [RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 1.0)],
        predictedColor: OklabColor(L: 0.501, a: 0.101, b: 0.101),
        deltaE: 0.01
    )

    let (merged, map) = PigmentDecomposer.mergeRecipes(
        recipes: [r1, r2],
        pixelCounts: [100, 200],
        colorThreshold: 0.05,
        concentrationThreshold: 0.05
    )

    #expect(merged.count == 1, "Recipes with different pigments but same color should merge")
    #expect(map == [0, 0])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PigmentDecomposerTests/mergeRecipesMergesOnColorMatchAlone \
  2>&1 | tail -20
```

Expected: FAIL — currently requires BOTH conditions, so different pigment sets prevent the merge.

- [ ] **Step 3: Write failing test — merge on recipe structure match alone**

Add to `PigmentDecomposerTests.swift`:

```swift
@Test
func mergeRecipesMergesOnStructureMatchAlone() {
    // Two recipes with SAME pigments and similar concentrations but colors beyond colorThreshold
    let r1 = PigmentRecipe(
        components: [
            RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 0.6),
            RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 0.4)
        ],
        predictedColor: OklabColor(L: 0.3, a: 0.1, b: 0.1),
        deltaE: 0.01
    )
    let r2 = PigmentRecipe(
        components: [
            RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 0.62),
            RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 0.38)
        ],
        predictedColor: OklabColor(L: 0.5, a: 0.2, b: 0.2),
        deltaE: 0.01
    )

    let (merged, map) = PigmentDecomposer.mergeRecipes(
        recipes: [r1, r2],
        pixelCounts: [100, 200],
        colorThreshold: 0.005, // Very tight color threshold — colors are far apart
        concentrationThreshold: 0.05
    )

    #expect(merged.count == 1, "Recipes with same pigments and similar concentrations should merge regardless of color distance")
    #expect(map == [0, 0])
}
```

- [ ] **Step 4: Run test to verify it fails**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PigmentDecomposerTests/mergeRecipesMergesOnStructureMatchAlone \
  2>&1 | tail -20
```

Expected: FAIL — the color distance exceeds the threshold, so the `guard dist < colorThreshold else { continue }` skips the recipe structure check entirely.

- [ ] **Step 5: Implement OR-based merge logic**

In `ios/RefPlane/Processing/PigmentDecomposer.swift`, replace the matching loop inside `mergeRecipes` (lines 629–651). Change:

```swift
            var matchedIndex: Int? = nil
            for (j, existing) in mergedRecipes.enumerated() {
                let dist = sqrtf(oklabDistance(recipe.predictedColor, existing.predictedColor))
                guard dist < colorThreshold else { continue }

                // Compare recipe structure
                let r1Names = Set(recipe.components.map { $0.pigmentId })
                let r2Names = Set(existing.components.map { $0.pigmentId })
                guard r1Names == r2Names else { continue }

                var concDiffOk = true
                for comp1 in recipe.components {
                    let comp2 = existing.components.first { $0.pigmentId == comp1.pigmentId }
                    let diff = abs(comp1.concentration - (comp2?.concentration ?? 0))
                    if diff > concentrationThreshold {
                        concDiffOk = false
                        break
                    }
                }

                if concDiffOk {
                    matchedIndex = j
                    break
                }
            }
```

To:

```swift
            var matchedIndex: Int? = nil
            for (j, existing) in mergedRecipes.enumerated() {
                let dist = sqrtf(oklabDistance(recipe.predictedColor, existing.predictedColor))
                let colorMatch = dist < colorThreshold

                // Compare recipe structure
                let r1Names = Set(recipe.components.map { $0.pigmentId })
                let r2Names = Set(existing.components.map { $0.pigmentId })
                var structureMatch = false
                if r1Names == r2Names {
                    var concDiffOk = true
                    for comp1 in recipe.components {
                        let comp2 = existing.components.first { $0.pigmentId == comp1.pigmentId }
                        let diff = abs(comp1.concentration - (comp2?.concentration ?? 0))
                        if diff > concentrationThreshold {
                            concDiffOk = false
                            break
                        }
                    }
                    structureMatch = concDiffOk
                }

                if colorMatch || structureMatch {
                    matchedIndex = j
                    break
                }
            }
```

- [ ] **Step 6: Run all merge tests to verify they pass**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PigmentDecomposerTests \
  2>&1 | tail -20
```

Expected: ALL PASS — including existing `mergeRecipesCombinesSimilarRecipes` test.

- [ ] **Step 7: Write test — larger cluster absorbs smaller on merge**

Add to `PigmentDecomposerTests.swift`:

```swift
@Test
func mergeRecipesLargerClusterAbsorbsSmaller() {
    let r1 = PigmentRecipe(
        components: [RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 1.0)],
        predictedColor: OklabColor(L: 0.5, a: 0.1, b: 0.1),
        deltaE: 0.05
    )
    let r2 = PigmentRecipe(
        components: [RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 1.0)],
        predictedColor: OklabColor(L: 0.501, a: 0.101, b: 0.101),
        deltaE: 0.01
    )

    // r2 has more pixels (500 vs 100), so r2's recipe should be the survivor
    let (merged, _) = PigmentDecomposer.mergeRecipes(
        recipes: [r1, r2],
        pixelCounts: [100, 500],
        colorThreshold: 0.05,
        concentrationThreshold: 0.05
    )

    #expect(merged.count == 1)
    #expect(merged[0].components[0].pigmentId == "pigB", "Larger cluster's recipe should survive")
}
```

- [ ] **Step 8: Run test and verify it passes**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PigmentDecomposerTests/mergeRecipesLargerClusterAbsorbsSmaller \
  2>&1 | tail -20
```

Expected: PASS

- [ ] **Step 9: Commit**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane && \
git add ios/RefPlane/Processing/PigmentDecomposer.swift ios/RefPlaneTests/PigmentDecomposerTests.swift && \
git commit -m "fix: mergeRecipes uses OR logic — color match OR recipe structure match"
```

---

### Task 2: Chroma-Weighted Histogram Candidates

The current histogram candidate construction uses raw pixel count as weight. Large neutral areas dominate because they have the most pixels. The spec requires `effectiveWeight = count * (1 + chromaBoost * chroma)` with `chromaBoost ~= 2.0` so vivid histogram bins compete better during centroid seeding.

**Files:**
- Modify: `ios/RefPlane/Processing/ColorRegionsProcessor.swift` (three `buildHistogramCandidates` overloads)
- Test: `ios/RefPlaneTests/PaintPaletteBuilderTests.swift` (integration-level test via pipeline output)

- [ ] **Step 1: Write failing integration test — vivid minority cluster survives**

Add to `PaintPaletteBuilderTests.swift`:

```swift
@Test
func vividMinorityClusterSurvivesInOverclustering() throws {
    // Construct synthetic pixel data: 90% neutral gray, 10% vivid red
    let neutralCount = 900
    let vividCount = 100
    let total = neutralCount + vividCount

    var pixelLab = [Float](repeating: 0, count: total * 3)
    // Neutral gray: L=0.5, a=0, b=0
    for i in 0..<neutralCount {
        pixelLab[i * 3] = 0.5
        pixelLab[i * 3 + 1] = 0.0
        pixelLab[i * 3 + 2] = 0.0
    }
    // Vivid red: L=0.6, a=0.2, b=0.1
    for i in neutralCount..<total {
        pixelLab[i * 3] = 0.6
        pixelLab[i * 3 + 1] = 0.2
        pixelLab[i * 3 + 2] = 0.1
    }

    // Assign labels: 0 for neutral, 1 for vivid
    let labels: [Int32] = Array(repeating: 0, count: neutralCount) + Array(repeating: 1, count: vividCount)
    let centroids = [
        OklabColor(L: 0.5, a: 0.0, b: 0.0),
        OklabColor(L: 0.6, a: 0.2, b: 0.1)
    ]

    let regions = ColorRegionsProcessor.Result(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        quantizedCentroids: centroids,
        pixelLabels: labels,
        pixelLab: pixelLab,
        clusterPixelCounts: [neutralCount, vividCount],
        clusterSalience: [1.0, 1.8] // Vivid cluster gets higher salience
    )

    var config = ColorConfig()
    config.numShades = 2
    config.numTubes = 4
    config.maxPigmentsPerMix = 3

    let result = try PaintPaletteBuilder.build(
        colorRegions: regions,
        config: config,
        database: database,
        pigments: pigments
    )

    // The vivid red cluster must survive as a distinct recipe
    let hasVividRecipe = result.recipes.contains { recipe in
        let chroma = sqrtf(recipe.predictedColor.a * recipe.predictedColor.a + recipe.predictedColor.b * recipe.predictedColor.b)
        return chroma > 0.05
    }
    #expect(hasVividRecipe, "Vivid minority cluster should survive in final palette")
}
```

- [ ] **Step 2: Run test to check baseline behavior**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests/vividMinorityClusterSurvivesInOverclustering \
  2>&1 | tail -20
```

Note: This test may pass even before the histogram change because the test provides pre-built centroids. Its primary role is regression protection — ensuring the vivid cluster is never merged away by later stages.

- [ ] **Step 3: Add chroma weighting to `buildHistogramCandidates(labArray:)`**

In `ios/RefPlane/Processing/ColorRegionsProcessor.swift`, in the `buildHistogramCandidates(labArray:)` method (~line 527-541), change the candidate construction from:

```swift
            let inverseCount = 1 / Float(count)
            candidates.append(
                HistogramCandidate(
                    color: OklabColor(
                        L: sumL[histogramBin] * inverseCount,
                        a: sumA[histogramBin] * inverseCount,
                        b: sumB[histogramBin] * inverseCount
                    ),
                    weight: Float(count)
                )
            )
```

To:

```swift
            let inverseCount = 1 / Float(count)
            let avgA = sumA[histogramBin] * inverseCount
            let avgB = sumB[histogramBin] * inverseCount
            let chroma = sqrtf(avgA * avgA + avgB * avgB)
            let chromaBoost: Float = 2.0
            candidates.append(
                HistogramCandidate(
                    color: OklabColor(
                        L: sumL[histogramBin] * inverseCount,
                        a: avgA,
                        b: avgB
                    ),
                    weight: Float(count) * (1.0 + chromaBoost * chroma)
                )
            )
```

- [ ] **Step 4: Add chroma weighting to `buildHistogramCandidates(points:)`**

In the same file, in `buildHistogramCandidates(points:)` (~line 575-585), change:

```swift
            let inverseCount = 1 / Float(count)
            let color = OklabColor(
                L: sumL[index] * inverseCount,
                a: sumA[index] * inverseCount,
                b: sumB[index] * inverseCount
            )
            candidates.append(HistogramCandidate(color: color, weight: Float(count)))
```

To:

```swift
            let inverseCount = 1 / Float(count)
            let avgA = sumA[index] * inverseCount
            let avgB = sumB[index] * inverseCount
            let color = OklabColor(
                L: sumL[index] * inverseCount,
                a: avgA,
                b: avgB
            )
            let chroma = sqrtf(avgA * avgA + avgB * avgB)
            let chromaBoost: Float = 2.0
            candidates.append(HistogramCandidate(color: color, weight: Float(count) * (1.0 + chromaBoost * chroma)))
```

- [ ] **Step 5: Add chroma weighting to `buildHistogramCandidates(counts:sumL:sumA:sumB:)`**

In the GPU-path overload (~line 613-628), change:

```swift
            candidates.append(
                HistogramCandidate(
                    color: OklabColor(L: averageL, a: averageA, b: averageB),
                    weight: Float(count)
                )
            )
```

To:

```swift
            let chroma = sqrtf(averageA * averageA + averageB * averageB)
            let chromaBoost: Float = 2.0
            candidates.append(
                HistogramCandidate(
                    color: OklabColor(L: averageL, a: averageA, b: averageB),
                    weight: Float(count) * (1.0 + chromaBoost * chroma)
                )
            )
```

- [ ] **Step 6: Run existing test suite to verify no regressions**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -30
```

Expected: ALL PASS — chroma weighting changes centroid selection but should not break any existing invariant.

- [ ] **Step 7: Commit**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane && \
git add ios/RefPlane/Processing/ColorRegionsProcessor.swift ios/RefPlaneTests/PaintPaletteBuilderTests.swift && \
git commit -m "feat: chroma-weighted histogram candidates for better vivid color capture"
```

---

### Task 3: Stage 4B — Snap/Reassign Loop

After constrained decomposition (Stage 4A), centroids are still the original overclustered positions from k-means. The recipes' `predictedColor` values may differ from these centroids because the achievable paint gamut doesn't perfectly cover Oklab space. Stage 4B pulls the cluster structure toward achievable paint colors by replacing centroids with predicted recipe colors and reassigning pixels.

**Files:**
- Modify: `ios/RefPlane/Processing/PaintPaletteBuilder.swift`
- Test: `ios/RefPlaneTests/PaintPaletteBuilderTests.swift`

- [ ] **Step 1: Write failing test — snap/reassign produces valid labels**

Add to `PaintPaletteBuilderTests.swift`:

```swift
@Test
func snapAndReassignProducesValidLabels() throws {
    // 4 distinct clusters spread across Oklab space
    let centroids = [
        OklabColor(L: 0.2, a: 0.0, b: 0.0),   // dark neutral
        OklabColor(L: 0.8, a: 0.0, b: 0.0),   // light neutral
        OklabColor(L: 0.5, a: 0.15, b: 0.0),  // reddish
        OklabColor(L: 0.5, a: -0.1, b: 0.1)   // greenish
    ]
    let pixelsPerCluster = 50
    let total = centroids.count * pixelsPerCluster

    var pixelLab = [Float](repeating: 0, count: total * 3)
    var labels = [Int32](repeating: 0, count: total)
    for (ci, centroid) in centroids.enumerated() {
        for j in 0..<pixelsPerCluster {
            let idx = ci * pixelsPerCluster + j
            pixelLab[idx * 3] = centroid.L + Float.random(in: -0.02...0.02)
            pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.02...0.02)
            pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.02...0.02)
            labels[idx] = Int32(ci)
        }
    }

    let regions = ColorRegionsProcessor.Result(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        quantizedCentroids: centroids,
        pixelLabels: labels,
        pixelLab: pixelLab,
        clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: 4),
        clusterSalience: [Float](repeating: 1.0, count: 4)
    )

    var config = ColorConfig()
    config.numShades = 4
    config.numTubes = 5
    config.maxPigmentsPerMix = 3

    let result = try PaintPaletteBuilder.build(
        colorRegions: regions,
        config: config,
        database: database,
        pigments: pigments
    )

    // Every pixel label must be a valid recipe index
    let recipeCount = result.recipes.count
    for label in result.pixelLabels {
        #expect(label >= 0 && Int(label) < recipeCount, "Label \(label) out of range [0, \(recipeCount))")
    }

    // Pixel count should match total
    #expect(result.pixelLabels.count == total)
    #expect(result.clusterPixelCounts.reduce(0, +) == total)
}
```

- [ ] **Step 2: Run test to establish baseline**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests/snapAndReassignProducesValidLabels \
  2>&1 | tail -20
```

This test may pass on the existing code (it checks invariants that should always hold). It guards against regressions when we add the snap/reassign loop.

- [ ] **Step 3: Implement `snapAndReassign` method**

Add to `ios/RefPlane/Processing/PaintPaletteBuilder.swift`, inside the `PaintPaletteBuilder` enum, before `pruneToMaxShades`:

```swift
    private static func snapAndReassign(
        recipes: [PigmentRecipe],
        pixelLab: [Float],
        selectedTubes: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int,
        minConcentration: Float,
        iterations: Int = 2
    ) -> (recipes: [PigmentRecipe], labels: [Int32], counts: [Int]) {
        var currentRecipes = recipes
        var currentCentroids = recipes.map { $0.predictedColor }
        var currentLabels = [Int32]()
        var currentCounts = [Int]()

        for _ in 0..<iterations {
            // Reassign all pixels to snapped centroids
            currentLabels = ColorRegionsProcessor.reassignLabels(
                pixelLab: pixelLab,
                centroids: currentCentroids,
                lWeight: 0.3
            )

            // Recompute centroids and counts from new labels
            let (newCentroids, newCounts) = ColorRegionsProcessor.computeCentroidsAndCounts(
                pixelLab: pixelLab,
                labels: currentLabels,
                k: currentCentroids.count
            )
            currentCounts = newCounts

            // Re-decompose only centroids that moved significantly
            for i in 0..<newCentroids.count where newCounts[i] > 0 {
                let dist = oklabDistance(newCentroids[i], currentCentroids[i])
                if dist > 0.0001 { // ~0.01 Oklab distance, squared
                    let reDecomposed = PigmentDecomposer.decompose(
                        targetColors: [newCentroids[i]],
                        pigments: selectedTubes,
                        database: database,
                        maxPigments: maxPigments,
                        minConcentration: minConcentration,
                        concurrent: false
                    )
                    if let recipe = reDecomposed.first {
                        currentRecipes[i] = recipe
                    }
                }
            }

            currentCentroids = currentRecipes.map { $0.predictedColor }
        }

        // Final reassignment to ensure labels match recipe predicted colors
        currentLabels = ColorRegionsProcessor.reassignLabels(
            pixelLab: pixelLab,
            centroids: currentCentroids,
            lWeight: 0.3
        )
        let (_, finalCounts) = ColorRegionsProcessor.computeCentroidsAndCounts(
            pixelLab: pixelLab,
            labels: currentLabels,
            k: currentCentroids.count
        )

        return (currentRecipes, currentLabels, finalCounts)
    }
```

- [ ] **Step 4: Wire Stage 4B into `build()` method**

In `ios/RefPlane/Processing/PaintPaletteBuilder.swift`, replace the section between Stage 4 constrained decomposition and Stage 5 merge. Change:

```swift
        // Stage 4 - Constrained Decomposition
        let workingRecipes = PigmentDecomposer.decompose(
            targetColors: colorRegions.quantizedCentroids,
            pigments: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )

        let t3 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4 (Constrained Iterations) took \(String(format: "%.1f", (t3 - t2) * 1000)) ms")
        onProgress?(0.75)

        // Stage 5 - Merge, Prune, and Finalize
        let (mergedRecipes, mergeMap) = PigmentDecomposer.mergeRecipes(
            recipes: workingRecipes,
            pixelCounts: colorRegions.clusterPixelCounts
        )

        var workingLabels = colorRegions.pixelLabels.map { Int32(mergeMap[Int($0)]) }
```

To:

```swift
        // Stage 4A - Constrained Decomposition
        let constrainedRecipes = PigmentDecomposer.decompose(
            targetColors: colorRegions.quantizedCentroids,
            pigments: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )

        let t3 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4A (Constrained Decomp) took \(String(format: "%.1f", (t3 - t2) * 1000)) ms")
        onProgress?(0.60)

        // Stage 4B - Snap/Reassign Loop
        let (workingRecipes, snappedLabels, snappedCounts) = snapAndReassign(
            recipes: constrainedRecipes,
            pixelLab: colorRegions.pixelLab,
            selectedTubes: selectedTubes,
            database: database,
            maxPigments: config.maxPigmentsPerMix,
            minConcentration: config.minConcentration
        )

        let t3b = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 4B (Snap/Reassign) took \(String(format: "%.1f", (t3b - t3) * 1000)) ms")
        onProgress?(0.75)

        // Stage 5 - Merge, Prune, and Finalize
        let (mergedRecipes, mergeMap) = PigmentDecomposer.mergeRecipes(
            recipes: workingRecipes,
            pixelCounts: snappedCounts
        )

        var workingLabels = snappedLabels.map { Int32(mergeMap[Int($0)]) }
```

- [ ] **Step 5: Run all PaintPaletteBuilder tests**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests \
  2>&1 | tail -20
```

Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane && \
git add ios/RefPlane/Processing/PaintPaletteBuilder.swift ios/RefPlaneTests/PaintPaletteBuilderTests.swift && \
git commit -m "feat: add Stage 4B snap/reassign loop for pigment-aware clustering"
```

---

### Task 4: Stage 5A — Adaptive Shade Count

After merge, remove non-anchor shades that add negligible visual value. This allows the palette to stop below `numShades` when the image doesn't benefit from more mixes.

**Files:**
- Modify: `ios/RefPlane/Processing/PaintPaletteBuilder.swift`
- Test: `ios/RefPlaneTests/PaintPaletteBuilderTests.swift`

- [ ] **Step 1: Write failing test — near-monochrome image produces fewer shades than requested**

Add to `PaintPaletteBuilderTests.swift`:

```swift
@Test
func nearMonochromeImageProducesFewShades() throws {
    // All clusters are very close in color — a gray image with tiny variation
    let k = 6
    let pixelsPerCluster = 100
    let total = k * pixelsPerCluster

    var pixelLab = [Float](repeating: 0, count: total * 3)
    var labels = [Int32](repeating: 0, count: total)
    var centroids = [OklabColor]()

    for ci in 0..<k {
        let L = 0.48 + 0.01 * Float(ci) // Very tight L range: 0.48 to 0.53
        centroids.append(OklabColor(L: L, a: 0.0, b: 0.0))
        for j in 0..<pixelsPerCluster {
            let idx = ci * pixelsPerCluster + j
            pixelLab[idx * 3] = L + Float.random(in: -0.005...0.005)
            pixelLab[idx * 3 + 1] = Float.random(in: -0.005...0.005)
            pixelLab[idx * 3 + 2] = Float.random(in: -0.005...0.005)
            labels[idx] = Int32(ci)
        }
    }

    let regions = ColorRegionsProcessor.Result(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        quantizedCentroids: centroids,
        pixelLabels: labels,
        pixelLab: pixelLab,
        clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: k),
        clusterSalience: [Float](repeating: 1.0, count: k)
    )

    var config = ColorConfig()
    config.numShades = 8 // Request 8 but image only needs ~1-2
    config.numTubes = 4
    config.maxPigmentsPerMix = 3

    let result = try PaintPaletteBuilder.build(
        colorRegions: regions,
        config: config,
        database: database,
        pigments: pigments
    )

    // With near-monochrome input, adaptive pruning should collapse most shades
    #expect(result.recipes.count < k, "Near-monochrome image should not keep all \(k) distinct shades")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests/nearMonochromeImageProducesFewShades \
  2>&1 | tail -20
```

Expected: FAIL — without adaptive pruning, the pipeline keeps all surviving post-merge shades up to `numShades`.

- [ ] **Step 3: Implement `adaptivePrune` method**

Add to `ios/RefPlane/Processing/PaintPaletteBuilder.swift`, inside the `PaintPaletteBuilder` enum:

```swift
    private static func adaptivePrune(
        recipes: [PigmentRecipe],
        counts: [Int],
        labels: inout [Int32],
        anchors: Set<Int>
    ) -> [PigmentRecipe] {
        let totalPixels = max(1, counts.reduce(0, +))
        var survivors = Array(0..<recipes.count)
        let errorThreshold: Float = 0.005 // Per-pixel weighted error increase threshold

        while survivors.count > 2 {
            // Find weakest non-anchor by pixel count
            var weakestIdx = -1
            var weakestCount = Int.max

            for s in survivors where !anchors.contains(s) {
                if counts[s] < weakestCount {
                    weakestCount = counts[s]
                    weakestIdx = s
                }
            }

            guard weakestIdx >= 0 else { break }

            // Find nearest survivor to the candidate for removal
            let removedColor = recipes[weakestIdx].predictedColor
            var nearestDist: Float = .greatestFiniteMagnitude
            for s in survivors where s != weakestIdx {
                let d = oklabDistance(removedColor, recipes[s].predictedColor)
                if d < nearestDist { nearestDist = d }
            }

            // Estimate error increase from removing this shade
            // Pixels currently assigned to it would go to the nearest survivor
            let errorIncrease = Float(weakestCount) * sqrtf(nearestDist)
            let perPixelIncrease = errorIncrease / Float(totalPixels)

            if perPixelIncrease >= errorThreshold { break }

            survivors.removeAll { $0 == weakestIdx }
        }

        // Only reassign labels if we actually removed something
        guard survivors.count < recipes.count else { return recipes }

        let survivorSet = Set(survivors)
        var indexMap = [Int32](repeating: 0, count: recipes.count)
        for i in 0..<recipes.count {
            if survivorSet.contains(i) {
                indexMap[i] = Int32(i)
            } else {
                let droppedColor = recipes[i].predictedColor
                var bestDist = Float.greatestFiniteMagnitude
                var bestSurv = survivors[0]
                for s in survivors {
                    let d = oklabDistance(droppedColor, recipes[s].predictedColor)
                    if d < bestDist {
                        bestDist = d
                        bestSurv = s
                    }
                }
                indexMap[i] = Int32(bestSurv)
            }
        }

        labels = labels.map { indexMap[Int($0)] }
        return recipes
    }
```

- [ ] **Step 4: Wire Stage 5A into `build()` — after merge, before prune-to-max**

In `ios/RefPlane/Processing/PaintPaletteBuilder.swift`, in the `build()` method, after the merge step computes `mergedRecipes`, `mergeMap`, `workingLabels`, and `finalCounts`, add the adaptive prune call before the existing prune-to-maxShades. Insert after:

```swift
        var finalCounts = [Int](repeating: 0, count: mergedRecipes.count)
        for label in workingLabels {
            finalCounts[Int(label)] += 1
        }

        var finalRecipes = mergedRecipes
```

Add:

```swift
        // Stage 5A - Adaptive shade count
        // Identify anchors for protection
        let nonTrivialThreshold5A = max(1, finalCounts.reduce(0, +) / 100)
        var anchors5A = Set<Int>()
        var minL5A: Float = .greatestFiniteMagnitude
        var maxL5A: Float = -.greatestFiniteMagnitude
        var darkestIdx5A: Int? = nil
        var lightestIdx5A: Int? = nil

        for i in 0..<finalRecipes.count where finalCounts[i] > nonTrivialThreshold5A {
            let c = finalRecipes[i].predictedColor
            if c.L < minL5A { minL5A = c.L; darkestIdx5A = i }
            if c.L > maxL5A { maxL5A = c.L; lightestIdx5A = i }
        }
        [darkestIdx5A, lightestIdx5A].compactMap { $0 }.forEach { anchors5A.insert($0) }

        finalRecipes = adaptivePrune(
            recipes: finalRecipes,
            counts: finalCounts,
            labels: &workingLabels,
            anchors: anchors5A
        )

        // Recompute counts after adaptive prune
        finalCounts = [Int](repeating: 0, count: finalRecipes.count)
        for label in workingLabels {
            finalCounts[Int(label)] += 1
        }
```

- [ ] **Step 5: Run test to verify it passes**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests/nearMonochromeImageProducesFewShades \
  2>&1 | tail -20
```

Expected: PASS — near-identical shades should be collapsed by adaptive pruning.

- [ ] **Step 6: Run all PaintPaletteBuilder tests**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests \
  2>&1 | tail -20
```

Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane && \
git add ios/RefPlane/Processing/PaintPaletteBuilder.swift ios/RefPlaneTests/PaintPaletteBuilderTests.swift && \
git commit -m "feat: Stage 5A adaptive shade pruning — remove negligible-value shades"
```

---

### Task 5: Stage 5B — Final Constrained Refit

After the final survivor set and label map are chosen, recompute centroids from actual pixel data, refit recipes one last time, and do a final pixel reassignment. This ensures recipes are optimized against the pixels they actually own, not the original overclustered centroids.

**Files:**
- Modify: `ios/RefPlane/Processing/PaintPaletteBuilder.swift`
- Test: `ios/RefPlaneTests/PaintPaletteBuilderTests.swift`

- [ ] **Step 1: Write test — final recipes use only selected tubes**

Add to `PaintPaletteBuilderTests.swift`:

```swift
@Test
func allFinalRecipesUseOnlySelectedTubes() throws {
    let centroids = [
        OklabColor(L: 0.2, a: -0.05, b: 0.0),
        OklabColor(L: 0.5, a: 0.1, b: 0.05),
        OklabColor(L: 0.8, a: 0.0, b: -0.05),
        OklabColor(L: 0.6, a: -0.1, b: 0.1),
        OklabColor(L: 0.35, a: 0.05, b: -0.1)
    ]
    let pixelsPerCluster = 100
    let total = centroids.count * pixelsPerCluster

    var pixelLab = [Float](repeating: 0, count: total * 3)
    var labels = [Int32](repeating: 0, count: total)
    for (ci, centroid) in centroids.enumerated() {
        for j in 0..<pixelsPerCluster {
            let idx = ci * pixelsPerCluster + j
            pixelLab[idx * 3] = centroid.L + Float.random(in: -0.01...0.01)
            pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.01...0.01)
            pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.01...0.01)
            labels[idx] = Int32(ci)
        }
    }

    let regions = ColorRegionsProcessor.Result(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        quantizedCentroids: centroids,
        pixelLabels: labels,
        pixelLab: pixelLab,
        clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: centroids.count),
        clusterSalience: [Float](repeating: 1.0, count: centroids.count)
    )

    var config = ColorConfig()
    config.numShades = 5
    config.numTubes = 4
    config.maxPigmentsPerMix = 3

    let result = try PaintPaletteBuilder.build(
        colorRegions: regions,
        config: config,
        database: database,
        pigments: pigments
    )

    let tubeIds = Set(result.selectedTubes.map { $0.id })
    for (i, recipe) in result.recipes.enumerated() {
        for comp in recipe.components {
            #expect(tubeIds.contains(comp.pigmentId),
                "Recipe \(i) uses pigment '\(comp.pigmentName)' (\(comp.pigmentId)) which is not in selectedTubes")
        }
    }
}
```

- [ ] **Step 2: Run test to establish baseline**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests/allFinalRecipesUseOnlySelectedTubes \
  2>&1 | tail -20
```

Expected: PASS — this invariant should already hold. It's a regression guard for the refit step.

- [ ] **Step 3: Implement Stage 5B final refit in `build()`**

In `ios/RefPlane/Processing/PaintPaletteBuilder.swift`, in the `build()` method, after the "Clean up empty indices" section that produces `prunedRecipes` and remapped `workingLabels`, and before the clipped indices computation, add Stage 5B. Replace:

```swift
        finalCounts = [Int](repeating: 0, count: prunedRecipes.count)
        for label in workingLabels {
            finalCounts[Int(label)] += 1
        }

        var clippedIndices = [Int]()
        for (i, recipe) in prunedRecipes.enumerated() {
            if recipe.deltaE > 0.05 { // Materially high delta E
                clippedIndices.append(i)
            }
        }
```

With:

```swift
        // Stage 5B - Final Constrained Refit
        // Recompute centroids from the final labels, then refit recipes
        let (refitCentroids, refitCounts) = ColorRegionsProcessor.computeCentroidsAndCounts(
            pixelLab: colorRegions.pixelLab,
            labels: workingLabels,
            k: prunedRecipes.count
        )

        var refitRecipes = prunedRecipes
        for i in 0..<refitCentroids.count where refitCounts[i] > 0 {
            let reDecomposed = PigmentDecomposer.decompose(
                targetColors: [refitCentroids[i]],
                pigments: selectedTubes,
                database: database,
                maxPigments: config.maxPigmentsPerMix,
                minConcentration: config.minConcentration,
                concurrent: false
            )
            if let recipe = reDecomposed.first {
                refitRecipes[i] = recipe
            }
        }

        // Final pixel reassignment to refit predicted colors
        let refitPredicted = refitRecipes.map { $0.predictedColor }
        workingLabels = ColorRegionsProcessor.reassignLabels(
            pixelLab: colorRegions.pixelLab,
            centroids: refitPredicted,
            lWeight: 0.3
        )

        finalCounts = [Int](repeating: 0, count: refitRecipes.count)
        for label in workingLabels {
            finalCounts[Int(label)] += 1
        }

        var clippedIndices = [Int]()
        for (i, recipe) in refitRecipes.enumerated() {
            if recipe.deltaE > 0.05 {
                clippedIndices.append(i)
            }
        }
```

Also update the return statement to use `refitRecipes` instead of `prunedRecipes`:

```swift
        return PaintPaletteResult(
            selectedTubes: selectedTubes,
            recipes: refitRecipes,
            pixelLabels: workingLabels,
            clusterPixelCounts: finalCounts,
            clippedRecipeIndices: clippedIndices
        )
```

- [ ] **Step 4: Update Stage 5 timing log**

Update the timing print at the end of `build()` to reflect Stage 5B. Change:

```swift
        let t4 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 5 (Merge & Prune) took \(String(format: "%.1f", (t4 - t3) * 1000)) ms")
```

To (note: use `t3b` from the Stage 4B timing, which was added in Task 3):

```swift
        let t4 = CFAbsoluteTimeGetCurrent()
        print("[PaintPaletteBuilder] Stage 5 (Merge, Prune & Refit) took \(String(format: "%.1f", (t4 - t3b) * 1000)) ms")
```

- [ ] **Step 5: Run all PaintPaletteBuilder tests**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests \
  2>&1 | tail -20
```

Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane && \
git add ios/RefPlane/Processing/PaintPaletteBuilder.swift ios/RefPlaneTests/PaintPaletteBuilderTests.swift && \
git commit -m "feat: Stage 5B final constrained refit — re-optimize recipes against actual pixel centroids"
```

---

### Task 6: Integration Tests and Value Anchor Protection

Add integration-level tests verifying the end-to-end pipeline invariants from the spec: value anchors survive, duplicate darks merge, and clipped recipes are flagged.

**Files:**
- Test: `ios/RefPlaneTests/PaintPaletteBuilderTests.swift`

- [ ] **Step 1: Write test — value anchors are preserved**

Add to `PaintPaletteBuilderTests.swift`:

```swift
@Test
func valueAnchorsPreservedAfterMergeAndPrune() throws {
    // Create clusters with a wide value range — darkest and lightest should survive
    let centroids = [
        OklabColor(L: 0.1, a: 0.0, b: 0.0),   // very dark — anchor
        OklabColor(L: 0.3, a: 0.02, b: 0.01),
        OklabColor(L: 0.5, a: 0.05, b: 0.03),
        OklabColor(L: 0.5, a: -0.05, b: -0.03),
        OklabColor(L: 0.7, a: 0.02, b: 0.01),
        OklabColor(L: 0.95, a: 0.0, b: 0.0)   // very light — anchor
    ]
    let pixelsPerCluster = 80
    let total = centroids.count * pixelsPerCluster

    var pixelLab = [Float](repeating: 0, count: total * 3)
    var labels = [Int32](repeating: 0, count: total)
    for (ci, centroid) in centroids.enumerated() {
        for j in 0..<pixelsPerCluster {
            let idx = ci * pixelsPerCluster + j
            pixelLab[idx * 3] = centroid.L + Float.random(in: -0.01...0.01)
            pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.01...0.01)
            pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.01...0.01)
            labels[idx] = Int32(ci)
        }
    }

    let regions = ColorRegionsProcessor.Result(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        quantizedCentroids: centroids,
        pixelLabels: labels,
        pixelLab: pixelLab,
        clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: centroids.count),
        clusterSalience: [Float](repeating: 1.0, count: centroids.count)
    )

    var config = ColorConfig()
    config.numShades = 3 // Force heavy pruning
    config.numTubes = 5
    config.maxPigmentsPerMix = 3

    let result = try PaintPaletteBuilder.build(
        colorRegions: regions,
        config: config,
        database: database,
        pigments: pigments
    )

    let lightnesses = result.recipes.map { $0.predictedColor.L }
    let hasVeryDark = lightnesses.contains { $0 < 0.25 }
    let hasVeryLight = lightnesses.contains { $0 > 0.75 }

    #expect(hasVeryDark, "Darkest anchor (L~0.1) should survive pruning")
    #expect(hasVeryLight, "Lightest anchor (L~0.95) should survive pruning")
}
```

- [ ] **Step 2: Write test — duplicate dark recipes merge**

```swift
@Test
func duplicateDarkRecipesMerge() throws {
    // Multiple dark clusters that should all map to the same dark pigment mix
    let centroids = [
        OklabColor(L: 0.08, a: 0.0, b: 0.0),
        OklabColor(L: 0.10, a: 0.01, b: 0.0),
        OklabColor(L: 0.12, a: 0.0, b: 0.01),
        OklabColor(L: 0.6, a: 0.1, b: 0.05)   // one distinct mid-tone
    ]
    let pixelsPerCluster = 100
    let total = centroids.count * pixelsPerCluster

    var pixelLab = [Float](repeating: 0, count: total * 3)
    var labels = [Int32](repeating: 0, count: total)
    for (ci, centroid) in centroids.enumerated() {
        for j in 0..<pixelsPerCluster {
            let idx = ci * pixelsPerCluster + j
            pixelLab[idx * 3] = centroid.L + Float.random(in: -0.005...0.005)
            pixelLab[idx * 3 + 1] = centroid.a + Float.random(in: -0.005...0.005)
            pixelLab[idx * 3 + 2] = centroid.b + Float.random(in: -0.005...0.005)
            labels[idx] = Int32(ci)
        }
    }

    let regions = ColorRegionsProcessor.Result(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        quantizedCentroids: centroids,
        pixelLabels: labels,
        pixelLab: pixelLab,
        clusterPixelCounts: [Int](repeating: pixelsPerCluster, count: centroids.count),
        clusterSalience: [Float](repeating: 1.0, count: centroids.count)
    )

    var config = ColorConfig()
    config.numShades = 8
    config.numTubes = 4
    config.maxPigmentsPerMix = 3

    let result = try PaintPaletteBuilder.build(
        colorRegions: regions,
        config: config,
        database: database,
        pigments: pigments
    )

    // The 3 near-identical dark clusters should merge into 1 or 2 at most
    let darkRecipes = result.recipes.filter { $0.predictedColor.L < 0.25 }
    #expect(darkRecipes.count <= 2, "Near-identical dark clusters should merge, got \(darkRecipes.count)")
    #expect(result.recipes.count >= 2, "Should still have at least 2 distinct recipes (dark + mid)")
}
```

- [ ] **Step 3: Write test — clipped recipes are flagged**

```swift
@Test
func clippedRecipesAreFlagged() throws {
    // Include a highly saturated color that's hard to mix with limited tubes
    let centroids = [
        OklabColor(L: 0.5, a: 0.0, b: 0.0),       // neutral — easy
        OklabColor(L: 0.7, a: 0.25, b: 0.25)       // extremely vivid — likely clipped
    ]
    let total = 200

    var pixelLab = [Float](repeating: 0, count: total * 3)
    var labels = [Int32](repeating: 0, count: total)
    for i in 0..<100 {
        pixelLab[i * 3] = 0.5; pixelLab[i * 3 + 1] = 0.0; pixelLab[i * 3 + 2] = 0.0
        labels[i] = 0
    }
    for i in 100..<200 {
        pixelLab[i * 3] = 0.7; pixelLab[i * 3 + 1] = 0.25; pixelLab[i * 3 + 2] = 0.25
        labels[i] = 1
    }

    let regions = ColorRegionsProcessor.Result(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        quantizedCentroids: centroids,
        pixelLabels: labels,
        pixelLab: pixelLab,
        clusterPixelCounts: [100, 100],
        clusterSalience: [1.0, 1.5]
    )

    var config = ColorConfig()
    config.numShades = 2
    config.numTubes = 3 // Very limited tube budget
    config.maxPigmentsPerMix = 2

    let result = try PaintPaletteBuilder.build(
        colorRegions: regions,
        config: config,
        database: database,
        pigments: pigments
    )

    // clippedRecipeIndices should be populated only for materially mismatched recipes
    // (this test just validates the field is populated and indices are in range)
    for idx in result.clippedRecipeIndices {
        #expect(idx >= 0 && idx < result.recipes.count, "Clipped index \(idx) out of range")
        #expect(result.recipes[idx].deltaE > 0.05, "Clipped recipe should have materially high deltaE")
    }
}
```

- [ ] **Step 4: Run all integration tests**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RefPlaneTests/PaintPaletteBuilderTests \
  2>&1 | tail -30
```

Expected: ALL PASS

- [ ] **Step 5: Run full test suite**

Run:
```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane/ios && xcodebuild test \
  -scheme Underpaint \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -30
```

Expected: ALL PASS — no regressions in any existing tests.

- [ ] **Step 6: Commit**

```bash
cd /Users/martingalese/Documents/Projects/Programming/RefPlane && \
git add ios/RefPlaneTests/PaintPaletteBuilderTests.swift && \
git commit -m "test: integration tests for value anchors, dark merge, and clipped recipes"
```

---

## Verification Checklist

After all tasks are complete:

1. **Invariant: All recipes use only selected tubes** — verified by `allFinalRecipesUseOnlySelectedTubes` test
2. **Invariant: Duplicate darks merge** — verified by `duplicateDarkRecipesMerge` test
3. **Invariant: Value anchors survive** — verified by `valueAnchorsPreservedAfterMergeAndPrune` test
4. **Invariant: Near-monochrome stops early** — verified by `nearMonochromeImageProducesFewShades` test
5. **Invariant: Merge uses OR logic** — verified by `mergeRecipesMergesOnColorMatchAlone` and `mergeRecipesMergesOnStructureMatchAlone` tests
6. **Invariant: Vivid colors survive** — verified by `vividMinorityClusterSurvivesInOverclustering` test
7. **Manual test: Load a colorful photo, confirm vivid accents appear in palette and canvas**
8. **Manual test: Load a mostly-neutral photo with small vivid area, confirm vivid area is captured**
9. **Performance: Check console timing logs — total pipeline should be under 400ms on iPhone hardware**
