# Paint Palette Pipeline Redesign

## Problem

The current color study + paint mixing pipeline has three architectural issues:

1. **Two-stage disconnect.** K-means clusters the image in Oklab space, then each cluster is independently decomposed into a pigment recipe. K-means doesn't know what pigments can produce, so it may select centroids far from any achievable paint mix — leading to muted, inaccurate approximations.

2. **No global pigment budget.** Each recipe independently draws from all ~20 essential pigments. A real artist picks 5–8 tubes and uses only those for every mix. Without this constraint, the output scatters 12+ pigments across recipes with no coherent limited palette.

3. **No deduplication.** Multiple k-means centroids (especially darks and neutrals) decompose to the same or nearly identical recipe, wasting palette slots that could capture more visual variety.

## Goals (in priority order)

1. Capture the most salient colors of the image
2. Use a minimal number of individual pigments (tubes)
3. Use a minimal number of distinct mixes (shades)

## Architecture: Sequential Five-Stage Pipeline

### Stage 1 — Overcluster

Run the existing histogram-seeded k-means in Oklab space with `k = min(2 × numShades, 48)`. This gives a broad set of representative colors. The overclustering ensures important colors aren't lost before deduplication.

Uses existing `ColorRegionsProcessor` with `lWeight: 1.0` and `spreadBias` from the Palette Spread setting. No changes to the clustering algorithm itself.

Output: overclustered centroids, pixel labels, pixel counts per cluster.

### Stage 2 — Preliminary Decomposition

Decompose each overclustered centroid against the full ~20 essential pigments (unconstrained). This is the existing `PigmentDecomposer.decompose()` — cheap for ≤48 colors.

Purpose: discover which pigments the image "wants to use" before constraining.

### Stage 3 — Tube Selection

Select the top N pigments (user's tube count) by weighted frequency:

```
score(pigment) = Σ (concentration_in_recipe × pixel_count_of_cluster)
```

This weights pigments by how much of the mix they represent and how much image area uses them. A pigment at 10% concentration covering 80% of pixels scores higher than one at 90% covering 1%.

**Tiebreaker:** When two pigments are within 10% of each other's score, prefer the one whose masstone is farthest (in Oklab) from all already-selected pigments. This prevents selecting redundant earth tones when a blue would extend the gamut.

**Edge case:** If the image uses fewer pigments than requested, cap at what's actually needed.

### Stage 4 — Constrained Decomposition + Snap

Re-decompose each centroid using only the N selected tubes. The existing `PigmentDecomposer` lookup table and Nelder-Mead machinery are reused, but built against the tube subset. This dramatically shrinks the lookup table (e.g., 6 tubes → ~291 entries vs ~1,540 for 20 pigments).

After constrained decomposition, run a snap-reassign loop (2 iterations):

1. Replace each centroid with its recipe's `predictedColor` (snapping into the achievable gamut)
2. Re-assign all pixels to the nearest snapped centroid (reuse existing GPU `kmeansAssign`)
3. Recompute centroids from pixel means
4. Re-decompose centroids that shifted significantly (Oklab distance > 0.01)

Two iterations are sufficient for stability. Skip re-decomposition for centroids that barely moved.

### Stage 5 — Merge & Finalize

Identify duplicate recipe pairs by two criteria:

1. **Recipe structure match:** Same pigment set, all concentrations within ±5 percentage points.
2. **Color match:** Predicted colors within Oklab distance < 0.015 (~ΔE₀₀ 1.5, below most people's discrimination threshold).

When merging, the cluster with more pixels absorbs the smaller. Drop empty clusters. If the surviving count still exceeds `numShades`, drop the smallest clusters by pixel count until at or below target.

Floor at 2 surviving shades (minimum meaningful palette).

Final pass: re-assign all pixels to surviving centroids, build the output image from recipe predicted colors.

## Data Model

### ColorConfig

```swift
struct ColorConfig {
    var numShades: Int         = 12   // upper bound; actual count may be fewer after merging
    var numTubes: Int          = 6    // pigment budget
    var paletteSpread: Double  = 0    // histogram seeding bias (0=mass, 1=hue)
    var maxPigmentsPerMix: Int = 3    // max pigments in a single recipe
}
```

Removed: `paintMixEnabled` (paint mixing is always on in color mode).

### ColorRegionsProcessor.Result

Adds `clusterPixelCounts: [Int]` — pixel count per cluster, needed for tube selection weighting.

### ProcessingResult

`pigmentRecipes` becomes non-optional (always present in color mode). Gains `selectedTubes: [PigmentData]`.

### PaintPaletteResult (new)

Returned by `PaintPaletteBuilder` (Stages 2–5):

```swift
struct PaintPaletteResult {
    let selectedTubes: [PigmentData]
    let recipes: [PigmentRecipe]
    let convergenceLabel: [Int]  // maps overcluster label → final recipe index
}
```

## File Changes

### ColorRegionsProcessor.swift — Minimal changes

- `process()` gains an explicit `overclusterK: Int?` parameter (default `nil`). When provided, it overrides the internal `config.numShades` for k-means cluster count. `ImageProcessor` passes `min(2 × numShades, 48)`.
- `Result` gains `clusterPixelCounts: [Int]`.
- Everything else unchanged.

### PigmentDecomposer.swift — Major expansion

New public API:

- `selectTubes(preliminaryRecipes:pixelCounts:maxTubes:allPigments:) → [PigmentData]` — Stage 3
- `decomposeConstrained(targetColors:tubes:database:maxPigments:) → [PigmentRecipe]` — Stage 4 (reuses existing internals with tube-scoped lookup table)
- `mergeRecipes(recipes:pixelCounts:colorThreshold:concentrationThreshold:) → (recipes: [PigmentRecipe], labelMapping: [Int])` — Stage 5

Existing `buildLookupTable`, `findBestRecipe`, `refineConcentrations` internals are parameterized by pigment subset rather than hardcoded to all essentials.

### ImageProcessor.swift — Pipeline orchestrator

The `.color` case becomes:

1. `ColorRegionsProcessor.process()` with `k = min(2 × numShades, 48)`
2. `PigmentDecomposer.decompose()` unconstrained (Stage 2)
3. `PigmentDecomposer.selectTubes()` (Stage 3)
4. `PigmentDecomposer.decomposeConstrained()` with selected tubes (Stage 4)
5. Snap centroids to predicted colors, GPU re-assign pixels, iterate (Stage 4 loop)
6. `PigmentDecomposer.mergeRecipes()` (Stage 5)
7. Final pixel remap + image build

### AppModels.swift

`ColorConfig` drops `paintMixEnabled`, adds `numTubes: Int = 6`.

### ColorSettingsView.swift

Adds "Tubes" slider (3–10, default 6). Removes Paint Mixing toggle. Max Pigments slider is always visible.

### PaletteView.swift

Adds a "Tubes" summary header listing the selected pigment names above the recipe list.

### SpectralData.swift

Adds `PaintPaletteResult` struct.

## UI Controls

| Control | Range | Default | Purpose |
|---------|-------|---------|---------|
| Shades | 2–24 | 12 | Upper bound on distinct mixes |
| Tubes | 3–10 | 6 | Number of pigments in the limited palette |
| Palette Spread | 0–1 | 0 | Bias toward hue diversity in clustering |
| Max Pigments | 1–3 | 3 | Max pigments per individual mix |

## Performance Budget

| Stage | Estimated time |
|-------|---------------|
| 1. Overcluster (GPU) | ~50–100ms |
| 2. Preliminary decompose | ~50ms |
| 3. Tube selection | < 1ms |
| 4. Constrained decompose + 2 snap-reassign passes | ~90ms |
| 5. Merge + final remap | ~30ms |
| **Total** | **~250–350ms** |

## Merge Thresholds

- **Color match:** Oklab distance < 0.015
- **Recipe structure match:** Same pigments, concentrations within ±5 percentage points
- **Merge direction:** Larger cluster (by pixel count) absorbs smaller
- **Minimum survivors:** 2 shades

## Future Considerations

If tube selection quality proves insufficient with the frequency-based approach (Stage 3), the next step is joint optimization: formulate pigment selection and recipe assignment as a single optimization minimizing total reconstruction error subject to ≤ N tubes. The sequential pipeline structure makes this a drop-in replacement for Stage 3 only — no other stages need to change.
