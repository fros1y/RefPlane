# Paint Palette Pipeline Redesign

## Summary

Redesign color-mode paint mixing as a limited-palette pipeline:

1. Overcluster the image to avoid losing important colors early.
2. Use unconstrained decomposition only to discover which pigments the image wants.
3. Pick a global tube set once.
4. Re-decompose every color against that tube set.
5. Snap clusters into the achievable paint gamut, reassign pixels, and merge duplicates.

The result should look closer to a real painter's workflow: a small set of tubes reused across a small set of mixes, instead of many unrelated per-cluster recipes.

## Problem

The current color study + paint mixing pipeline has three structural issues:

1. Two-stage disconnect. The quantizer chooses centroids without knowing whether those colors are achievable by any real pigment mix, then the pigment solver tries to approximate them after the fact.
2. No global pigment budget. Each recipe can draw from the full essential set, but a real limited palette should reuse the same 5-8 tubes across all mixes.
3. No recipe deduplication. Different centroids, especially darks and neutrals, often collapse to the same or nearly identical recipe and waste palette slots.

## Goals

In priority order:

1. Capture the most salient colors in the source image.
2. Reuse a minimal global tube set across the whole palette.
3. Minimize the number of distinct final mixes without throwing away important image structure.
4. Preserve value anchors such as the darkest dark, lightest light, and dominant neutral when the image meaning depends on them.
5. Stay within the existing interactive budget for color mode on iPhone-class hardware.

## Non-Goals

- No joint global optimization in the first pass.
- No changes to tonal mode or value mode.
- No new pigment database or spectral model changes.
- No attempt to make color mode perfectly colorimetrically accurate.
- No broad UI redesign beyond controls needed for limited-palette behavior.

## Key Design Decisions

- Keep the current histogram-seeded centroid selection and GPU/CPU assignment machinery. This redesign changes how the color study result is consumed, not the entire color-region stack.
- Introduce a dedicated `PaintPaletteBuilder` to own stages 2-5. `ImageProcessor` should stay a thin coordinator.
- Make stage inputs and outputs explicit. The original draft depended on GPU reassignment in Stage 4 without exposing the pixel-space Oklab data needed to do it.
- Weight decisions by visual salience, not raw area alone. Small high-chroma or high-edge clusters should compete better than their pixel count alone would suggest.
- Optimize the selected tube set against constrained reconstruction error after the initial frequency pass, not only by unconstrained pigment popularity.
- Protect value anchors from being merged away unless the replacement is genuinely equivalent.
- Treat `numShades` as an upper bound, not a promise. Merging can produce fewer final mixes.
- Preserve a graceful fallback. If the limited-palette pass fails, color mode should still return the plain color study rather than fail the whole processing request.

## Pipeline Overview

### Stage 1 - Overcluster

Use the existing color-region pipeline to generate more working centroids than the requested final shade count:

`requestedShades = max(2, numShades)`

`overclusterK = min(2 * requestedShades, 48)`

Notes:

- This is not a brand-new clustering system. It is the existing histogram-seeded centroid selection plus assignment/recompute pass in `ColorRegionsProcessor`.
- Use `lWeight = 0.3` for the overclustering step. With `lWeight = 1.0`, k-means forms clusters dominated by luminance bands (light-beige, mid-beige, dark-neutral) because real images have more luminance variation than chroma variation. Small vivid areas (flowers, accents) get absorbed into luminance-matched neutral clusters. A lower lWeight prioritizes hue separation, ensuring those accents survive as distinct clusters that later stages can evaluate.
- Apply chroma-aware weighting in the histogram candidate construction: `effectiveWeight = count × (1 + chromaBoost × chroma)` with `chromaBoost ≈ 2.0`. This makes vivid histogram bins "louder" during centroid seeding, so high-chroma minority colors compete with large neutral areas even before overclustering begins.
- Keep using `paletteSpread` as the histogram seeding bias.
- Stage 1 only overclusters. It does not try to enforce the final tube budget yet.

Required output:

- `quantizedCentroids: [OklabColor]`
- `pixelLabels: [Int32]`
- `clusterPixelCounts: [Int]`
- `clusterSalience: [Float]`
- `pixelLab: [Float]`

`pixelLab` is required so Stage 4 can reassign pixels to snapped centroids without re-running RGB-to-Oklab conversion.

`clusterSalience` is a bounded multiplier derived from factors such as cluster chroma, local edge density, and distance from the image-wide mean color. It should increase the importance of visually meaningful accents without allowing tiny outliers to dominate the palette.

### Stage 2 - Preliminary Decomposition

Decompose each Stage 1 centroid against the full essential pigment set with the existing solver.

Purpose:

- Discover which pigments the image repeatedly wants before imposing a global tube budget.
- Reuse the current `PigmentDecomposer.decompose(...)` logic for this pass.

Input:

- `quantizedCentroids`
- all essential pigments
- `maxPigmentsPerMix`

Output:

- one unconstrained `PigmentRecipe` per overcluster centroid

### Stage 3 - Tube Selection

Choose the global tube set by weighted usage:

```text
effectiveClusterWeight =
  clusterPixelCount * clusterSalience
```

```text
score(pigment) =
  sum(concentration_in_recipe * effectiveClusterWeight)
```

This favors pigments that matter in recipe weight, image area, and visual salience.

Selection rules:

- Seed the tube set with the top `numTubes` pigments by score.
- If two candidate pigments are within 10% of each other, prefer the one whose masstone is farthest in Oklab from the already-selected set. This extends gamut instead of overfilling one hue family.
- If fewer than `numTubes` pigments have meaningful nonzero use, keep fewer tubes.
- To prevent "tube churn" during minor parameter tweaks, introduce a slight hysteresis. If new scores are within a tiny margin of the previously selected tube set, prefer keeping the old tubes to avoid changing the whole palette over microscopic salience differences.
- After this stage, every later recipe must use only the selected tube set.

#### 3A. Salience weighting

The initial implementation should compute `clusterSalience` as a bounded multiplier rather than a hard gate.

Recommended inputs:

- centroid chroma, so vivid accents are not drowned out by large neutrals
- local edge density, so structurally important boundaries count more than flat fills
- distance from global mean color, so rare but meaningful hues compete better

The multiplier should be normalized to a narrow range such as `0.75...2.0`. This keeps the palette grounded in image mass while still protecting visually important small regions.

#### 3B. Local tube-set improvement

The score-ranked tube set is only the seed.

After seeding:

1. Recompute constrained recipes for the current tube set.
2. Measure total weighted reconstruction error using `effectiveClusterWeight`.
3. Run a bounded 1-for-1 swap search:
   replace one selected tube with one unselected pigment, keep the swap if total weighted constrained error improves.
4. Stop when no improving swap exists or the search budget is exhausted.

This is the first upgrade path before any heavier joint optimization.

### Stage 4 - Constrained Decomposition + Snap/Reassign

Re-decompose every working centroid using only the selected tubes, then pull the cluster structure toward the achievable paint gamut.

#### 4A. Constrained decomposition

- Build the lookup table against the selected tubes only.
- Reuse the existing lookup + refinement machinery, parameterized by pigment subset.
- Enforce `maxPigmentsPerMix` as before.
- Enforce a minimum concentration threshold (e.g., `0.02` or 2%). Snap physically impossible micro-additions to zero and accept the slight Oklab distance penalty to keep the recipe realistic for a human to mix.

#### 4B. Snap/reassign loop

Run two iterations:

1. Replace each working centroid with its recipe `predictedColor`.
2. Reassign all pixels to the snapped centroids using `ColorRegionsProcessor` reassignment helpers.
3. Recompute centroids and `clusterPixelCounts` from the new labels.
4. Re-decompose only centroids that moved by more than `0.01` in Oklab distance.

Rules:

- Do not silently fabricate gray fallback centroids for empty clusters during this stage. The reassignment helper used here must return counts alongside centroids so empty clusters are explicit and can be dropped or merged later.
- Two iterations are the initial target. If profiling shows instability, make the iteration count configurable behind an internal constant rather than hardcoding behavior in multiple places.

### Stage 5 - Merge, Prune, and Finalize

Merge duplicate or near-duplicate recipes using both structure and color:

1. Recipe structure match:
   same pigment ID set and all concentrations within `0.05`
2. Color match:
   predicted colors within Oklab distance `< 0.015`

Merge rules:

- The larger cluster absorbs the smaller.
- Drop empty clusters.
- Identify value anchors before merge/drop:
  - darkest anchor: lowest-lightness surviving cluster with nontrivial weight
  - lightest anchor: highest-lightness surviving cluster with nontrivial weight
  - dominant neutral anchor: lowest-chroma cluster with the highest effective cluster weight among neutral candidates
- Do not merge or drop an anchor unless the replacement is near-equivalent in lightness, chroma, and weighted reconstruction error.
- Treat `numShades` as an upper bound.
- If the surviving count still exceeds `numShades`, prune the lowest-value non-anchor clusters first.
- If the surviving count is below `numShades`, do not add artificial shades back.
- Allow a single surviving shade for effectively monochrome images. Otherwise, target a practical floor of 2 shades when the image actually needs more than one value family.

#### 5A. Adaptive shade count

Do not keep shades just because the user requested a larger maximum.

After merge and anchor protection, repeatedly test whether removing the weakest non-anchor cluster raises total weighted reconstruction error by more than a small internal threshold. If not, remove it.

This allows the final palette to stop early when the next shade adds negligible value.

#### 5B. Final constrained refit

After the final survivor set and label map are chosen:

1. Recompute centroids from the final labels.
2. Refit each surviving recipe one last time against those centroids using the selected tube set.
3. Recompute recipe error metrics from this final fit.

Finalization:

- Reassign pixels one last time to the surviving recipe colors.
- Build the rendered image from recipe `predictedColor`.
- Mark any surviving recipe whose final constrained error remains materially high as a limited-coverage recipe.
- Return the final recipes, selected tubes, final labels, counts, and any limited-coverage indicators.

## Architecture and Ownership

### `ColorRegionsProcessor.swift`

Minimal but important changes:

- `process(...)` gains `overclusterK: Int? = nil`
- `Result` gains:
  - `pixelLab: [Float]`
  - `clusterPixelCounts: [Int]`
  - `clusterSalience: [Float]`
- Add public helpers for reuse by the paint-palette pipeline:
  - `reassignLabels(pixelLab:centroids:lWeight:) -> [Int32]`
  - `computeCentroidsAndCounts(pixelLab:labels:k:) -> (centroids: [OklabColor], counts: [Int])`

Rationale:

- Stage 4 needs assignment and centroid recomputation against arbitrary centroids after pigment snapping.
- Those helpers already exist internally. Making them reusable is cleaner than duplicating logic in `ImageProcessor` or `PaintPaletteBuilder`.

### `PaintPaletteBuilder.swift` (new)

Own stages 2-5.

Public API:

```swift
struct PaintPaletteResult {
    let selectedTubes: [PigmentData]
    let recipes: [PigmentRecipe]
    let pixelLabels: [Int32]
    let clusterPixelCounts: [Int]
    let clippedRecipeIndices: [Int]
}

enum PaintPaletteBuilder {
    static func build(
        colorRegions: ColorRegionsProcessor.Result,
        config: ColorConfig,
        database: SpectralDatabase,
        pigments: [PigmentData]
    ) throws -> PaintPaletteResult
}
```

Rationale:

- This keeps `ImageProcessor` from becoming a second algorithm file.
- It gives the limited-palette flow one place to own invariants, heuristics, and future experimentation.

### `PigmentDecomposer.swift`

Keep the decomposition engine focused on recipe search primitives, but expand it with limited-palette helpers:

- `selectTubes(preliminaryRecipes:pixelCounts:clusterSalience:maxTubes:allPigments:) -> [PigmentData]`
- `improveTubeSet(seedTubes:targetColors:clusterWeights:allPigments:database:maxPigments:) -> [PigmentData]`
- `decompose(...)` should already work for arbitrary pigment subsets once lookup construction is parameterized properly
- `mergeRecipes(recipes:pixelCounts:colorThreshold:concentrationThreshold:) -> (recipes: [PigmentRecipe], labelMapping: [Int])`

Do not move the snap/reassign loop into `PigmentDecomposer`. That loop is about cluster geometry, not pigment search.

### `ImageProcessor.swift`

The `.color` path becomes:

1. Run `ColorRegionsProcessor.process(..., overclusterK: ...)`
2. Run `PaintPaletteBuilder.build(...)`
3. Render the output image and palette from the final recipes
4. Populate `ProcessingResult`

If the builder fails or returns no recipes, fall back to the plain color-study image and palette instead of failing the entire processing pass.

## Data Model Changes

### `ColorConfig`

```swift
struct ColorConfig {
    var numShades: Int = 12
    var numTubes: Int = 6
    var paletteSpread: Double = 0
    var maxPigmentsPerMix: Int = 3
    var minConcentration: Float = 0.02
}
```

Final product behavior removes `paintMixEnabled`; paint mixing is the color-mode output.

Implementation note:

- During rollout, it is acceptable to keep `paintMixEnabled` temporarily behind the scenes until the new pipeline is validated. The public design target is still to remove it.

### `ColorRegionsProcessor.Result`

Add:

```swift
let pixelLab: [Float]
let clusterPixelCounts: [Int]
let clusterSalience: [Float]
```

### `ProcessingResult`

Keep `pigmentRecipes` optional across all modes, but in `.color` it should be populated whenever the limited-palette pass succeeds.

Add:

```swift
let selectedTubes: [PigmentData]
let clippedRecipeIndices: [Int]
```

For non-color modes, `selectedTubes` and `clippedRecipeIndices` are empty.

### `AppState`

Add:

```swift
@Published var selectedTubes: [PigmentData] = []
@Published var clippedRecipeIndices: [Int] = []
```

This keeps the palette UI from having to infer the global tube set by unioning recipe components on the fly.

## UI Changes

### `ColorSettingsView.swift`

- Add a `Tubes` slider with range `3...10`, default `6`
- Remove the user-facing `Paint Mixing` toggle in the final design
- Keep `Max Pigments` visible in color mode

### `PaletteView.swift`

Add a `Tubes` summary above the recipe list:

- Show selected pigment names in order of Stage 3 selection
- Show a compact "Limited palette" warning when `clippedRecipeIndices` is non-empty
- Mark clipped recipes in the list so users can see which mixes are approximations rather than close matches.
  - Optional: To provide better Gamut Warning Context, display a split swatch for approximations showing the *Target Color* next to the *Achievable Mix*. This visually explains whether a clip is due to missing chroma or a slight value shift.
- Keep existing recipe rendering below the swatches

## Performance Budget

Target budget on modern iPhone hardware:

| Stage | Estimated time |
| --- | ---: |
| 1. Overcluster | 50-100 ms |
| 2. Preliminary decomposition | ~50 ms |
| 3. Tube selection + local search | 5-20 ms |
| 4. Constrained decomposition + 2 snap passes | 90-140 ms |
| 5. Merge, adaptive pruning, final refit + remap | 30-60 ms |
| Total | 225-370 ms |

This is a design target, not a promise. Validate with device measurements before removing rollout fallbacks.

## Testing Requirements

This redesign changes semantics, not just plumbing. It needs direct tests.

### Unit tests

- `PigmentDecomposerTests`
  - tube selection weights by concentration, cluster size, and cluster salience
  - local tube-swap search never worsens weighted constrained error
  - constrained decomposition never uses pigments outside the selected tube set
  - merge logic collapses near-identical recipes and preserves the larger cluster

- `PaintPaletteBuilderTests`
  - all final recipes use only `selectedTubes`
  - duplicate dark/neutral recipes merge down
  - value anchors are preserved unless an equivalent replacement exists
  - a near-monochrome image can legitimately finish with one surviving shade
  - requested `numTubes` larger than actual demand does not fabricate extra tubes
  - adaptive shade pruning can stop below `numShades` when the next shade has negligible value
  - limited-coverage recipes are flagged when final constrained error stays high

### Integration tests

- `ImageProcessor` color-mode result contains:
  - non-empty `selectedTubes`
  - `pigmentRecipes.count == palette.count`
  - no recipe component outside `selectedTubes`
  - `clippedRecipeIndices` is populated only for materially mismatched recipes

- CPU and GPU paths should be checked for broad parity with a tolerant perceptual threshold rather than exact byte equality.

## Rollout and Fallback

Recommended rollout:

1. Land the builder and helper APIs first.
2. Keep the old optional paint-mix path available internally during development.
3. Compare old vs new output on a small fixed image set.
4. Remove the public `Paint Mixing` toggle only after the limited-palette path is stable and performant.

Fallback rules:

- If Stage 2-5 fails, return the plain color-study result.
- Do not crash color mode because the pigment pipeline failed.
- Log enough timing and stage information to see whether failures are in tube selection, constrained decomposition, or snapping.

## Future Work

If Stage 3's score-based tube selection is not good enough, replace only that stage with a stronger optimization:

- joint tube selection + recipe assignment under a `<= numTubes` constraint
- beam search or mixed-integer approximation over the selected essential set

Later refinement, not part of the first implementation:

- "Bring Your Own Palette" (BYOP) / Tube Locking: Allow artists to explicitly lock in their physical paint inventory (or prefer a specific palette family), bypassing Stage 3 tube selection.
- Substrate / Paper Color Awareness: Let the user define a canvas or paper color, treating it as an always-available, zero-cost "tube" that lightens or tints recipes naturally.
- Gamut Visualization: An educational UI mode plotting the selected tube set as a 2D color wheel polygon, showing the image's original colors plotted inside (or clipped outside) the achievable gamut.

The rest of the pipeline can stay the same if Stage 3 is swapped later.
