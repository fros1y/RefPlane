# Underpaint — UX Interaction Scenarios & Evaluation Rubrics

## Purpose

This document defines common usage patterns for artists using Underpaint, formalizes them as interaction scenarios with step-by-step flows, and provides scoring rubrics to evaluate whether UX changes improve the experience. Each scenario represents a real task an artist would perform; the rubrics measure how well the app supports that task.

---

## Part 1 — Artist Personas & Usage Contexts

### Persona A: Studio Painter (Direct Reference)

An oil or acrylic painter working in a studio, painting from a photograph displayed on a tablet propped next to the easel. They need to extract value structure and a limited palette from the photo before starting, then reference the processed image throughout the painting session. Accuracy of paint recipes matters — they will physically mix the suggested pigments.

**Key needs:** Fast image load, clear value bands, accurate paint recipes, easy export, glanceable display at arm's length.

### Persona B: Plein Air Painter (Inspiration/Planning)

A landscape painter who photographs a scene on location, then uses the app in the field to quickly analyze the scene's value structure and dominant colors before that light condition changes. Speed is critical. They may never export — they just glance at the analysis, internalize it, and paint.

**Key needs:** Minimal taps from photo to analysis, fast processing, legible results on a phone screen in sunlight.

### Persona C: Watercolorist (Value-First Workflow)

A watercolorist who plans every painting with a value study before touching color. They typically work with 3–5 value bands, export the value study, print or trace it, then plan a limited palette (often 3–6 colors). They use Simplify to reduce photographic clutter and see the essential shapes.

**Key needs:** Fine control over value thresholds, simplification that preserves major shapes, easy toggling between value and color studies, export of both.

### Persona D: Illustration Student (Learning to See)

An art student using the app to train their eye. They repeatedly toggle between Original and processed modes to check their assumptions about value and color. They use the compare slider frequently. They experiment with settings to understand how value structure and color regions relate.

**Key needs:** Fast mode switching, responsive compare slider, low friction for experimentation, forgiving undo/reset behavior.

### Persona E: Portrait Artist (Subject Isolation)

A portrait painter who wants to isolate the figure from a busy background. They use Depth Effects to separate foreground and background, then apply value or color analysis to the isolated subject. Surface contours help them understand the 3D form of the face and figure.

**Key needs:** Precise depth cutoff control, clear foreground/background separation, contour overlay legibility, combined depth + value/color workflow.

---

## Part 2 — Common Usage Patterns

### Pattern 1: Quick Value Check

The artist loads a photo and switches to Value mode to see whether the scene has strong tonal structure. This is the simplest and most frequent use case — often completed in under 30 seconds.

**Flow:** Load image → tap Value → glance at result → optionally adjust band count → return to Original or close app.

### Pattern 2: Full Painting Preparation

The artist performs a complete analysis before starting a painting session: value study, color extraction, paint recipe review, and export of reference images. This is the most comprehensive workflow and touches nearly every feature.

**Flow:** Load image → Simplify → Value study (adjust thresholds) → export value study → Color study (adjust palette preset, review recipes) → export color study → prop device next to easel.

### Pattern 3: Palette Planning

The artist's primary goal is to determine which paints to squeeze onto the palette before a session. They switch to Color mode, select their available pigment tubes, and review the suggested recipes.

**Flow:** Load image → Color mode → select pigment preset or customize tube selection → adjust number of shades → review recipe cards → note pigments to use → close app, prepare palette.

### Pattern 4: Simplification for Composition

The artist uses Simplify and Kuwahara to strip away photographic detail and see the scene as broad, paintable shapes. This helps them assess the composition's strength and plan their block-in.

**Flow:** Load image → increase Simplify strength → adjust Kuwahara filter → toggle between Original (compare) and simplified → export simplified version for reference.

### Pattern 5: Depth-Assisted Portrait Study

The artist loads a portrait, enables Depth Effects to push the background away, then studies the subject's form with surface contours and value bands.

**Flow:** Load portrait → enable Depth Effects → adjust background cutoff → choose background mode (Blur or Remove) → enable Surface Contours → switch to Value mode → export.

### Pattern 6: Iterative Comparison

The artist repeatedly compares the original photo against various processed versions to evaluate which analysis settings best capture the scene's essential character.

**Flow:** Load image → process in one mode → activate Compare → drag slider → adjust settings → re-process → compare again → try different mode → compare again.

### Pattern 7: Band Isolation for Region Painting

In Color mode, the artist isolates individual color bands to see exactly which areas of the painting correspond to each mixed color. This helps plan the order of paint application.

**Flow:** Load image → Color mode → tap a palette swatch to isolate → see which canvas regions light up → tap another swatch → repeat → deselect to return to full view.

### Pattern 8: Grid Transfer

The artist overlays a grid on the processed image, then draws a matching grid on their canvas to transfer proportions accurately.

**Flow:** Load image → enable Grid → set divisions to match canvas grid → optionally enable diagonals → adjust line style for visibility → export with grid baked in → use at easel.

---

## Part 3 — UX Interaction Scenarios

Each scenario is a concrete, testable sequence of user actions with defined entry conditions, steps, and expected outcomes.

---

### Scenario 1: First Launch to First Value Study

**Persona:** Any (critical for first-time users)
**Pattern:** Quick Value Check
**Goal:** An artist who has never used the app loads a photo and sees a value study.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Opens app for the first time | Empty canvas with clear prompt to load an image |
| 2 | Taps image-load affordance | Photo library picker appears |
| 3 | Selects a photo | Image loads onto canvas; processing indicator if needed |
| 4 | Finds and taps "Value" mode | Mode switches; processing begins with progress feedback |
| 5 | Sees value study result | Canvas shows distinct tonal bands; palette/band count visible |
| 6 | Adjusts band count | Result updates responsively (< 1 s perceived latency) |

**Success criteria:**
- Steps 1–5 completable without any prior instruction or tutorial
- Total time from launch to seeing a value study < 20 seconds (excluding photo picker time and processing)
- The empty state communicates what to do next unambiguously
- Mode switching is discoverable (no hidden menus or gestures)

---

### Scenario 2: Complete Painting Prep Session

**Persona:** Studio Painter / Watercolorist
**Pattern:** Full Painting Preparation
**Goal:** Produce exported value and color studies ready for use at the easel.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Loads a photo from library | Image appears on canvas |
| 2 | Enables Simplify, adjusts strength | Simplified image renders; progress indicator during ML processing |
| 3 | Switches to Value mode | Value study appears on simplified image |
| 4 | Adjusts threshold distribution to "Shadows" | Thresholds redistribute, image updates |
| 5 | Adjusts band count to 5 | Five distinct tonal bands appear |
| 6 | Fine-tunes individual threshold handles | Immediate visual feedback; distribution auto-switches to "Custom" |
| 7 | Exports value study | Share sheet / file picker appears; image includes grid if enabled |
| 8 | Switches to Color mode | Color study renders on same simplified base |
| 9 | Selects "Zorn" palette preset | Palette updates; recipes use only Zorn pigments |
| 10 | Reviews paint recipes | Recipe cards visible, legible, grouped by dominant pigment |
| 11 | Exports color study | Second export completes |

**Success criteria:**
- Switching modes preserves the simplification setting (does not reset)
- Each config change triggers responsive reprocessing (< 2 s for Value, < 5 s for Color)
- Export produces a full-resolution image with overlays baked in
- Both exports are individually accessible after the session (not overwritten)
- Palette preset change triggers reprocessing automatically (no extra "apply" tap)

---

### Scenario 3: Palette Planning with Custom Tube Selection

**Persona:** Studio Painter
**Pattern:** Palette Planning
**Goal:** Determine which specific pigments to prepare based on the reference photo.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Loads photo, switches to Color mode | Color study renders; palette swatches and recipes appear |
| 2 | Opens Mixing section in inspector | Pigment preset picker and recipe cards visible |
| 3 | Selects "All" preset | Full 78-pigment library active; recipes may use any pigment |
| 4 | Reviews recipe list, notes which pigments appear most | Recipes are scannable; dominant pigments identifiable at a glance |
| 5 | Switches to "Custom" and disables pigments they don't own | Recipes update to use only enabled pigments |
| 6 | Adjusts max pigments per mix to 2 | Simpler recipes (2-pigment mixes) appear |
| 7 | Taps a palette swatch to isolate the band | Canvas highlights only the regions that map to that color |
| 8 | Notes the recipe for the isolated band | Recipe card is prominent when band is isolated |

**Success criteria:**
- Pigment enable/disable provides immediate visual feedback
- Disabling a pigment that appears in current recipes triggers re-computation
- The dominant pigment for each recipe is visually prominent (not buried in a list)
- Band isolation clearly highlights the canvas regions (strong visual contrast)
- The app prevents disabling all pigments (at least one must remain)

---

### Scenario 4: Quick Field Analysis (Phone, Bright Sunlight)

**Persona:** Plein Air Painter
**Pattern:** Quick Value Check + Palette Planning
**Goal:** Analyze a scene quickly outdoors on a phone before the light changes.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Opens app (was recently used; may still have previous image) | Previous session state or clear empty state — no ambiguous stale data |
| 2 | Loads new photo from camera roll | Previous image and processing state fully cleared |
| 3 | Switches to Value mode on phone | Value study renders; result legible on small screen |
| 4 | Glances at value structure, switches to Color | Color study renders quickly |
| 5 | Scans palette swatches | Colors are large enough to distinguish on phone |
| 6 | Puts the phone away and paints | — |

**Success criteria:**
- Loading a new image fully resets all previous processing state (no ghost state)
- Value study bands are distinguishable on a 6.1" phone display
- Color palette swatches are large enough to identify hue + value on phone
- Total interaction time (after photo selection) < 15 seconds excluding processing
- Results are legible outdoors (sufficient contrast, not dependent on subtle gradients)

---

### Scenario 5: Compare Slider Evaluation

**Persona:** Student / Any
**Pattern:** Iterative Comparison
**Goal:** Visually compare original photo against processed result to understand the transformation.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Has a processed image (any mode) on canvas | Processed result visible |
| 2 | Activates Compare mode | Split view appears with draggable divider |
| 3 | Drags divider left/right | Smooth, real-time reveal of before/after halves |
| 4 | With compare active, adjusts a setting (e.g., band count) | Image reprocesses; compare updates to show new result |
| 5 | Deactivates Compare | Returns to normal single-image canvas |

**Success criteria:**
- Compare divider tracks finger precisely with no lag
- Labels identify which side is "Original" and which is the processed version
- Adjusting settings while comparing does not require deactivating compare first
- Compare works in all modes (Tonal, Value, Color)
- Zoomed-in state is preserved when entering/exiting compare

---

### Scenario 6: Depth-Assisted Portrait Isolation

**Persona:** Portrait Artist
**Pattern:** Depth-Assisted Portrait Study
**Goal:** Isolate a portrait subject from a cluttered background and study its form.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Loads portrait photo | Image appears |
| 2 | Opens Depth section, enables Depth Effects | Depth model runs (progress indicator); depth map computed |
| 3 | Drags Background cutoff slider | Live preview shows foreground/background separation as slider moves |
| 4 | Fine-tunes cutoff to cleanly separate subject | Preview updates in real-time; foreground mask is reasonably clean |
| 5 | Selects "Remove" background mode | Background replaced with solid tone; subject isolated |
| 6 | Enables Surface Contours (20 levels) | Contour lines appear on subject, following facial/body form |
| 7 | Switches to Value mode | Value study renders on the isolated subject only |
| 8 | Exports combined result (value + contours + isolated) | Flattened export with all overlays baked in |

**Success criteria:**
- Depth slider provides real-time visual feedback (live threshold preview)
- Background removal produces a clean edge (acceptable minor artifacts)
- Contour lines follow meaningful depth gradients (not noise)
- Mode switching preserves depth isolation settings
- Export includes all visible overlays (depth effect + contours + value)

---

### Scenario 7: Grid Transfer Setup

**Persona:** Any (especially beginners)
**Pattern:** Grid Transfer
**Goal:** Set up a proportional grid overlay for transferring the image to canvas.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Has image loaded (any mode) | Image on canvas |
| 2 | Opens Structure section, enables Grid | Grid lines appear over image |
| 3 | Sets divisions to 4 | 4×4 grid displayed |
| 4 | Enables diagonals | Diagonal lines added to grid |
| 5 | Switches line style to "Auto" | Lines automatically contrast against underlying image content |
| 6 | Adjusts opacity to taste | Grid becomes more or less transparent |
| 7 | Zooms into a specific grid cell | Grid scales correctly with zoom; lines remain sharp |
| 8 | Exports image with grid | Exported image has grid permanently rendered at correct scale |

**Success criteria:**
- Grid is visible regardless of underlying image brightness (auto line style works)
- Grid cells are correctly proportioned (squares of equal size)
- Grid remains sharp at all zoom levels (vector rendering, not rasterized at display size)
- Exported grid lines are proportionally correct at full resolution
- Grid state persists across mode switches

---

### Scenario 8: Simplify + Kuwahara for Abstract Composition

**Persona:** Any artist assessing composition
**Pattern:** Simplification for Composition
**Goal:** Reduce a photograph to its essential compositional shapes.

| Step | User Action | Expected App Response |
|------|------------|----------------------|
| 1 | Loads photo | Image appears |
| 2 | Opens Study section, increases Simplify strength | ML model runs; progress indicator; simplified image replaces original |
| 3 | Increases Kuwahara filter strength | Painterly effect applied on top of simplification |
| 4 | Toggles Compare to see before/after | Split view shows dramatic difference between photo and simplified |
| 5 | Switches to Value mode on simplified image | Value study of the simplified image (broad, clear bands) |
| 6 | Switches back to Original mode | Sees simplified image (not raw photo) in Original mode |
| 7 | Exports simplified version | Exports the current simplified view |

**Success criteria:**
- Simplify + Kuwahara compose correctly (Kuwahara applied after ML simplification)
- Original mode with simplification shows the simplified image, not the raw photo
- Compare shows the raw original (pre-simplification) on the "before" side
- Adjusting Kuwahara does not re-run the full ML simplification (faster feedback)
- The distinction between Simplify (ML) and Kuwahara (filter) is clear in the UI

---

## Part 4 — Evaluation Rubrics

### How to Use These Rubrics

After making a UX change to the app, walk through the relevant scenarios and score each criterion. Compare scores before and after the change. A change that improves scores on its target scenario without degrading scores on other scenarios is a net positive. A change that improves one scenario at the cost of others requires judgment about which scenarios matter more for the target user base.

**Scoring:** Each criterion is scored 1–5.

| Score | Meaning |
|-------|---------|
| 1 | Fails — user cannot complete the action or is actively misled |
| 2 | Poor — user can complete the action but with significant friction, confusion, or errors |
| 3 | Adequate — user completes the action with minor friction or hesitation |
| 4 | Good — user completes the action smoothly with clear feedback |
| 5 | Excellent — action feels effortless, feedback is immediate and informative |

---

### Rubric A: Discoverability & First-Use Clarity

*Evaluates whether an artist new to the app can find and use features without instruction.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| A1 | Empty state clearly communicates "load an image to begin" | | |
| A2 | Mode selector (Original/Tonal/Value/Color) is immediately visible after image load | | |
| A3 | The relationship between modes and the inspector panel is obvious (i.e., relevant controls appear for the active mode) | | |
| A4 | Simplify and Kuwahara controls are findable without scrolling or navigating | | |
| A5 | Export action is discoverable without exploring every panel | | |
| A6 | The meaning of each mode is understandable from its name/icon alone | | |
| A7 | Adjusting a slider or toggle produces visible feedback within 1 second (or shows a progress indicator) | | |
| A8 | The user can return to the unprocessed photo from any state without confusion | | |

**Target scenarios:** Scenario 1, Scenario 4

---

### Rubric B: Processing Feedback & Perceived Performance

*Evaluates whether the app communicates what it's doing during heavy computation.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| B1 | A processing indicator appears within 200 ms of initiating a heavy operation | | |
| B2 | Progress feedback differentiates between determinate (known progress) and indeterminate (spinner) operations | | |
| B3 | The user can tell which operation is in progress (e.g., "Simplifying…" vs. "Processing value study…") | | |
| B4 | Cancellation is implicit when the user changes settings mid-processing (old result is discarded) | | |
| B5 | Stale results are never displayed (a completed result from a cancelled operation does not flash on screen) | | |
| B6 | After processing completes, the transition from indicator to result is smooth (no flicker, no layout shift) | | |
| B7 | For operations < 500 ms, no spinner appears (avoids flash of loading state) | | |

**Target scenarios:** Scenario 2, Scenario 4, Scenario 8

---

### Rubric C: Configuration Responsiveness

*Evaluates whether adjusting settings feels direct and responsive.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| C1 | Slider adjustments (band count, opacity, intensity) produce visual feedback within 500 ms | | |
| C2 | Threshold handle dragging updates the canvas in real-time (not on release) | | |
| C3 | Changing a preset (pigment palette, threshold distribution) triggers reprocessing automatically | | |
| C4 | Toggling overlays (grid, contours) takes effect immediately (no processing delay) | | |
| C5 | Rapid repeated changes (e.g., quickly sliding band count from 3→8) debounce correctly without queueing stale results | | |
| C6 | Adjusting Kuwahara strength does not re-trigger the full ML simplification | | |
| C7 | Mode switch preserves current simplification, depth, and overlay settings | | |

**Target scenarios:** Scenario 2, Scenario 3, Scenario 6

---

### Rubric D: State Coherence

*Evaluates whether the app maintains internally consistent state as the user navigates between features.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| D1 | Loading a new image fully resets all processing results (no ghost state from previous image) | | |
| D2 | Loading a new image preserves user-configured settings (grid divisions, palette preset, threshold distribution) | | |
| D3 | Switching modes preserves simplification and depth settings | | |
| D4 | Disabling then re-enabling depth effects restores the previous cutoff/mode/intensity | | |
| D5 | Switching from Color mode and back preserves the pigment selection and recipes | | |
| D6 | Compare view shows the correct "before" image (pre-simplification original) regardless of current mode | | |
| D7 | Export produces an image consistent with what's visible on screen (WYSIWYG) | | |
| D8 | Isolated band state clears when switching modes or loading a new image | | |

**Target scenarios:** Scenario 2, Scenario 4, Scenario 6

---

### Rubric E: Palette & Recipe Usability

*Evaluates how effectively the app communicates paint mixing information.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| E1 | Recipe cards are scannable — the dominant pigment for each mix is visually prominent | | |
| E2 | Pigment concentrations are expressed in a unit meaningful to painters (e.g., parts, not percentages) | | |
| E3 | Palette swatches are large enough to accurately judge color on the target device | | |
| E4 | Tapping a swatch to isolate a band provides clear, high-contrast canvas feedback | | |
| E5 | The relationship between a swatch and its recipe is unambiguous (which recipe belongs to which color) | | |
| E6 | Changing the pigment preset or tube selection triggers recipe re-computation with clear feedback | | |
| E7 | Recipes that require clipping (pigment exceeds concentration limit) are flagged visually | | |
| E8 | The user can determine which pigment tubes to prepare without reading every recipe in detail | | |

**Target scenarios:** Scenario 3, Scenario 7 (band isolation)

---

### Rubric F: Depth & Contour Interaction

*Evaluates the depth estimation and contour overlay workflow.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| F1 | Enabling depth effects provides clear feedback that a model is running | | |
| F2 | Background cutoff slider provides real-time visual preview (not just on release) | | |
| F3 | The depth cutoff preview clearly distinguishes foreground from background | | |
| F4 | Background mode options are understandable from their names | | |
| F5 | Contour lines follow meaningful depth gradients, not image noise | | |
| F6 | Contour density (levels slider) provides useful range: sparse enough to be readable, dense enough to show form | | |
| F7 | Depth settings persist when switching study modes | | |
| F8 | The combined result (depth + mode + overlays) is visually coherent, not cluttered | | |

**Target scenarios:** Scenario 6

---

### Rubric G: Canvas Interaction & Zoom

*Evaluates the image display, zoom, and navigation behavior.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| G1 | Pinch-to-zoom is smooth and responsive (60 fps) | | |
| G2 | Double-tap resets zoom to fit the image on screen | | |
| G3 | Overlays (grid, contours) scale correctly with zoom and remain sharp | | |
| G4 | Panning at high zoom does not overshoot or feel sluggish | | |
| G5 | Zoom state is preserved across mode switches | | |
| G6 | The canvas does not fight with the inspector panel for scroll gestures (no gesture conflicts) | | |
| G7 | Image appears at optimal size on both phone (compact) and tablet (regular) layouts | | |

**Target scenarios:** Scenario 7 (grid at zoom), Scenario 5 (compare at zoom)

---

### Rubric H: Export Quality & Workflow

*Evaluates the export path from canvas to share sheet.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| H1 | Export action is reachable in ≤ 2 taps from the canvas | | |
| H2 | Exported image matches the current canvas display (WYSIWYG) | | |
| H3 | Grid and contour overlays are correctly rendered in the export at full resolution | | |
| H4 | Export resolution is sufficient for printing or display at the target use case | | |
| H5 | Multiple sequential exports (e.g., value then color) do not overwrite each other | | |
| H6 | The share sheet offers contextually useful targets (Files, Photos, AirDrop) | | |
| H7 | Filename or metadata indicates what was exported (e.g., "Underpaint-Value-2026-04-03") | | |

**Target scenarios:** Scenario 2, Scenario 7

---

### Rubric I: Phone-Specific Usability

*Evaluates the experience on compact (iPhone) devices specifically.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| I1 | Inspector panel does not permanently obscure the canvas | | |
| I2 | The canvas area is large enough to evaluate the processed image | | |
| I3 | All controls are reachable without excessive scrolling in the drawer | | |
| I4 | Text labels on controls and recipes are legible at default Dynamic Type size | | |
| I5 | Touch targets for sliders, toggles, and swatches meet 44pt minimum | | |
| I6 | Palette swatches are large enough to distinguish similar hues | | |
| I7 | Mode selector is accessible without dismissing the drawer | | |

**Target scenarios:** Scenario 4

---

### Rubric J: Cross-Feature Composability

*Evaluates how well features combine when used together, as real artists do.*

| # | Criterion | Score (1–5) | Notes |
|---|-----------|-------------|-------|
| J1 | Simplify + Value mode produces clean, simplified value bands (not noisy) | | |
| J2 | Simplify + Color mode produces coherent color regions (not fragmented) | | |
| J3 | Depth isolation + Value/Color mode analyzes only the foreground | | |
| J4 | Grid overlay + any mode produces a useful composite for grid transfer | | |
| J5 | Contours + Value mode provides both tonal and dimensional information simultaneously | | |
| J6 | Band isolation + grid overlay highlights which grid cells contain the isolated color | | |
| J7 | Compare mode correctly shows original vs. the fully composited result (all effects applied) | | |

**Target scenarios:** Scenario 2, Scenario 6, Scenario 8

---

## Part 5 — Scenario-Rubric Mapping

Quick reference for which rubrics apply to which scenarios.

| Scenario | Primary Rubrics | Secondary Rubrics |
|----------|-----------------|-------------------|
| 1. First Value Study | A, B | G |
| 2. Complete Painting Prep | B, C, D, H | J |
| 3. Palette Planning | E, C | I |
| 4. Quick Field Analysis | A, B, I | D |
| 5. Compare Slider | G, C | D |
| 6. Depth Portrait | F, D, C | J, H |
| 7. Grid Transfer | G, H | J |
| 8. Simplify Composition | B, C, J | D |

---

## Part 6 — Conducting an Evaluation

### Before a UX Change

1. Walk through each scenario that the change targets (see mapping above).
2. Score every criterion in the applicable rubrics.
3. Note specific friction points, confusions, or failures in the "Notes" column.
4. Record the date and app version/commit.

### After the Change

1. Walk through the same scenarios.
2. Re-score every criterion.
3. Also walk through at least one unrelated scenario to check for regressions.
4. Compare scores. A positive change should:
   - Improve at least one criterion by ≥ 1 point on the target scenario
   - Not decrease any criterion by ≥ 1 point on unrelated scenarios
   - Not introduce any new score of 1 (failure) anywhere

### Recording Results

For each evaluation, record:

```
## Evaluation: [Change Description]
Date: YYYY-MM-DD
Commit: [hash]

### Scenario [N]: [Name]
| Criterion | Before | After | Delta | Notes |
|-----------|--------|-------|-------|-------|
| A1        | 3      | 4     | +1    | New empty state prompt is clearer |
| A2        | 4      | 4     |  0    | Unchanged |
| ...       |        |       |       |       |

### Regressions Checked
- Scenario [M]: No regressions observed
```

---

## Appendix: Scenario Coverage Matrix

Features touched by each scenario, for impact analysis when changing a specific feature.

| Feature | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 |
|---------|----|----|----|----|----|----|----|----|
| Image loading | x | x | x | x | | x | | x |
| Mode switching | x | x | x | x | x | x | | x |
| Value mode | x | x | | x | | x | | x |
| Color mode | | x | x | x | | | | |
| Simplify (ML) | | x | | | | | | x |
| Kuwahara filter | | x | | | | | | x |
| Threshold adjustment | | x | | | | | | |
| Pigment selection | | | x | | | | | |
| Paint recipes | | | x | | | | | |
| Band isolation | | | x | | | | | |
| Compare slider | | | | | x | | | x |
| Depth effects | | | | | | x | | |
| Contour overlay | | | | | | x | | |
| Grid overlay | | | | | | | x | |
| Export | | x | | | | x | x | x |
| Zoom/pan | | | | | x | | x | |
| Phone layout | | | | x | | | | |
