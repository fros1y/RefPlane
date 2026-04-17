# Clarity, Kit, Native — Pre-Launch Improvement Plan

**Date:** 2026-04-17
**Status:** Proposed
**Scope:** Pre-launch strong rewrite, user-facing bias

## Overview

The app is feature-complete and architecturally healthy, but three things are holding it back from a confident 1.0:

1. **Product mental model is fuzzy.** Two product names (*RefPlane* / *Underpaint*), three mode vocabularies, and three ways to change modes. Users will feel it before they can name it.
2. **The paywall doesn't earn $9.99.** The unlock gate is justified; the story told at the gate is not.
3. **The app produces screens, not artifacts.** The unique superpower — combining value + color + recipes + grid — is fragmented across toggles, and painters walk away with at most one of those views as a flat image.

This plan splits work into five workstreams. Workstream 0 (internal foundations) is a prerequisite; workstreams 1–4 are user-facing.

| # | Workstream | Why now |
|---|------------|---------|
| 0 | Internal foundations | Unblocks 1 and 2; touches most-modified files |
| 1 | Clarity rewrite | Returnable-proof launch; fixes naming + mode model |
| 2 | Painter's Kit — Composed Export | The single feature that justifies the ask |
| 3 | Painter's Kit — Sessions & Palettes | Retention / word-of-mouth features |
| 4 | Native feel | Risk-free polish; done last |

---

## Workstream 0 — Internal Foundations

### Goal

Make user-facing work cheaper and safer by consolidating three things that are currently scattered: mode mutation, processing lifecycle, and `AppState` surface area.

### Motivation

- `AppState` has ~30 forwarded getter/setters to `transform` / `depth` / `pipeline`. The decomposition landed; the compatibility shim never got removed. Every new call site has to pick which surface to touch.
- Five-plus functions touch `isProcessing` (`loadImage`, `triggerProcessing`, `applyAbstraction`, `applyDepthEffects`, cancellation paths). The ordering is correct today but fragile — the next feature that adds another async step will race.
- Mode mutation has three entrypoints: `setMode` (dock), `selectGrayscaleConversion` (inspector picker), `setUsesQuantization` (inspector toggle). All three arrive at the same place but along non-equivalent paths.

### Scope

**0.1 Remove the `AppState` forwarding layer.** Delete the ~30 computed properties that re-export `transform.*`, `depth.*`, `pipeline.*`. Update all call sites to access child state directly (`state.transform.activeMode`, not `state.activeMode`). This is a big, mechanical rename. Do it in one PR, behind a clear commit.

**0.2 One processing coordinator.** Introduce `ProcessingCoordinator` (actor or `@MainActor` final class) that owns the lifecycle of the pipeline: `start(for intent:)`, `cancel()`, `progress`. All async work (`abstract`, `depth`, `process`) goes through it. `isProcessing`, `processingLabel`, `processingProgress` become computed from coordinator state. `AppState.swift` shrinks materially.

**0.3 Single mode selector.** Collapse `setMode` + `selectGrayscaleConversion` + `setUsesQuantization` into one entrypoint. The inspector picker and quantize toggle become bindings on `state.transform.activeMode`; mode-specific config (grayscale conversion, quantize-on) moves *inside* the mode's own settings view, not the parent inspector. This is a small structural change with big downstream payoff — workstream 1's inspector flattening becomes mechanical.

### Files touched

- `ios/RefPlane/Models/AppState.swift` — shrinks significantly (forwarding deleted, coordinator extracted)
- `ios/RefPlane/Models/AppState+Depth.swift`, `AppState+Export.swift`, `AppState+FocusIsolation.swift`, `AppState+TransformPresets.swift` — move to coordinator-aware call sites
- New: `ios/RefPlane/Processing/ProcessingCoordinator.swift`
- `ios/RefPlane/Views/ControlPanelView.swift` — mode-mutating toggles migrate
- All view files reading `state.activeMode` etc. — updated to `state.transform.activeMode`

### Acceptance

- `grep -n "var activeMode:" ios/RefPlane/Models/AppState.swift` returns nothing.
- `isProcessing` is a computed property of one owner; no code outside `ProcessingCoordinator` writes it.
- Switching modes via dock, via grayscale picker, or via quantize toggle executes the same code path (observable via a single log line).
- Existing tests pass; regression tests for concurrency still green.

### Risks

- Forwarding cleanup is a huge diff. Mitigation: land as a single mechanical rename PR, reviewed for scope only, not content.
- `ProcessingCoordinator` extraction risks changing cancellation timing. Mitigation: port existing behavior 1:1 first, then simplify in a follow-up.

---

## Workstream 1 — Clarity Rewrite

### Goal

One name, one mode vocabulary, one way to select a mode, and a paywall that earns the ask. First-time users understand what the app does in under 30 seconds.

### 1.1 Single product name

**Decision: the product is _Underpaint_. _RefPlane_ is the internal project/repo name only.**

Audit and rename every user-facing surface to *Underpaint*:

- `ContentView.swift:320` — temp export dir `RefPlaneExports` → `UnderpaintExports`
- `ContentView.swift:352` — export filename prefix already `underpaint-*` ✓
- Xcode project display name, bundle display name (verify `Info.plist`)
- Paywall nav title ✓ already "Unlock Underpaint"
- README.md title still says "Underpaint" but internal docs reference "RefPlane" — leave code/repo references, fix anywhere user-visible
- `AppInstrumentation.swift` subsystem — leave as-is (developer-facing)

**Out of scope:** renaming the Swift module, repo, or Xcode project. Internal churn with no user-visible benefit.

### 1.2 Single mode vocabulary

**Decision: the four modes are _Original_, _Tonal_, _Value_, _Color_** — matching the user guide and marketing copy, not the current `RefPlaneMode.label` which says *Natural* / *Paletted*.

Changes:

- `AppModels.swift:8-15` — update `RefPlaneMode.label` to return the canonical names.
- Accept that the `enum` raw values stay `original/tonal/value/color` (they are, already) — no enum rename needed.
- Any view that hardcodes "Natural" or "Paletted" — there shouldn't be any; confirm with grep.

### 1.3 Single mode selector

**Decision: the mode dock is the only mode selector.** The inspector shows controls *for* the active mode; it does not switch modes.

Changes to `ControlPanelView.swift`:

- Delete the "Grayscale Conversion" top-level picker (lines 231-248). Grayscale method is a sub-setting of *Tonal* mode only; it belongs inside `ValueSettingsView`-equivalent for tonal.
- Delete the "Quantize" / "Limit Values" / "Limit Colors" toggle (lines 250-277). Quantization is implicit — selecting *Value* mode means "quantized grayscale", selecting *Color* mode means "quantized color". There is no un-quantized value/color mode worth exposing.
- The inspector becomes **mode-scoped**: show only the cards relevant to the active mode.

New inspector structure per mode:

| Mode | Inspector cards |
|------|----------------|
| Original | Simplify · Adjust Background · Overlays (Grid, Contours) |
| Tonal    | Simplify · Grayscale Method · Adjust Background · Overlays |
| Value    | Simplify · Value Settings (count + thresholds + distribution) · Adjust Background · Overlays |
| Color    | Simplify · Color Settings (count) · Palette · Adjust Background · Overlays |

This is simpler *and* removes the awkward "Turn on Limit Colors or Limit Values" placeholder text that's currently visible in Original/Tonal modes.

### 1.4 Collapse redundant threshold controls

`ValueSettingsView.swift` currently exposes both a `QuantizationBiasSlider` (continuous bias) *and* a `ThresholdSliderView` (manual per-threshold handles), with any manual drag auto-switching `distribution` to `.custom`. Users see two things that do overlapping work.

**Decision: show only the threshold handles.** Replace the bias slider with a "Distribute" popover/menu with three presets (Even / Shadow Detail / Light Detail) that one-shot-apply to the handles. The continuous bias is implementation detail, not a user concept.

### 1.5 Paywall rewrite

Current paywall (`PaywallView.swift`) has two feature rows: "Load any photo" and "Family Sharing". For $9.99 one-time, this is not a story.

**Decision: rewrite the paywall as a value-narrative, not a feature list.**

New structure:

- **Hero**: "Turn your photos into painting prep." Not "Process your own photos" (current).
- **What Underpaint does for painters** — three content rows, each with inline mini-screenshot (use SwiftUI Canvas/Images at fixed size):
  1. *See the values before you paint* — sample value-study render
  2. *Mix real paints, predicted physically* — sample recipe card with pigment names
  3. *Isolate your subject with Spatial depth* — sample portrait with depth cutoff
- **Privacy line** — "Every photo stays on your device. No accounts, no tracking."
- **Unlock button** — unchanged.
- **Restore / Redeem** — unchanged.

Ship 3 hero images as assets (screenshots of the real app on real references). This is where marketing polish earns a rating.

### 1.6 First-run education

The current empty state is a card with "Choose Photo" + "Browse Samples". Good, but it's a dead-end for someone who doesn't know what the modes do.

**Decision: the _Samples_ path doubles as the onboarding.** Curate 3-4 samples that *are* the tutorial:

- A portrait — demonstrates depth + value
- A landscape — demonstrates color + recipes
- A still life — demonstrates simplify + value

Each sample, on selection, drops the user straight into the most relevant mode with Simplify on and a light preset. Inline TipKit call-out on the mode dock for first-time samples: "Tap *Color* to see the palette recipes for this image."

This lets someone who's never painted understand the app in 30 seconds without a dedicated tutorial.

### Acceptance

- Grep for "RefPlane" in user-facing strings returns only internal/developer-facing hits.
- Grep for "Natural" or "Paletted" returns no UI strings.
- Only one code path sets `state.transform.activeMode`.
- Paywall shows 3 content rows with screenshot-grade imagery.
- First sample load → relevant mode auto-applied without user intervention.

### Risks

- Removing the grayscale picker loses the "Lightness / Average" alternatives (currently available even outside Tonal). These are rarely useful; still, confirm there's no user waiting on them. Mitigation: keep the options but surface only when Tonal is active.
- The single-selector rewrite changes the inspector's table of contents; reviewers may need to re-walk UX rubrics. Mitigation: re-score rubrics A, C, D after this lands (per `ux-scenarios-and-rubrics.md` Part 6).

---

## Workstream 2 — Painter's Kit, Phase 1: Composed Export

### Goal

Produce a single, high-quality, shareable artifact that represents the user's complete painting-prep work — not just the current mode.

### Motivation

Today: one export = one flat image of whatever view is currently on canvas. A painter doing full prep (scenario 2 in `ux-scenarios-and-rubrics.md`) exports two or three times, emails themselves the files, and reassembles at the easel.

The app already computes value, color, recipes, grid, and contours. It just doesn't produce the deliverable painters actually want: a **prep sheet** they can print, open on a tablet at the easel, or share with a student.

### 2.1 Prep Sheet design

**Decision: produce a PDF and a PNG, composed at export time, with a fixed layout:**

```
┌─────────────────────────────────────────────────┐
│  UNDERPAINT  |  <Filename>  |  <Date>            │
│                                                   │
│  ┌──────────────┐  ┌──────────────┐              │
│  │              │  │              │  VALUE        │
│  │  REFERENCE   │  │   VALUE      │  5 levels    │
│  │  (w/ grid)   │  │   STUDY      │  Shadow bias  │
│  └──────────────┘  └──────────────┘              │
│                                                   │
│  ┌──────────────┐   PALETTE + RECIPES            │
│  │              │   ● Cad Red Med    3 parts     │
│  │    COLOR     │   ● Yellow Ochre   1 part      │
│  │    STUDY     │   ● Titanium White 4 parts     │
│  └──────────────┘   (one row per mix)            │
│                                                   │
│  Kubelka-Munk · Golden Heavy Body Acrylics       │
└─────────────────────────────────────────────────┘
```

Single-page, print-friendly (US Letter + A4 variants generated from same layout, share sheet picks one).

### 2.2 Implementation notes

- Render each panel off-screen at export time using `ImageRenderer` (SwiftUI → UIImage) at a resolution pinned to the layout (not to the source image). Full-source-resolution compositing is wasteful and will OOM on older devices; target 300dpi at page size.
- Use existing processors (value, color, recipes) via the new `ProcessingCoordinator` to render each panel from the same source image with different `activeMode` configs — no new processing code, just multi-mode orchestration.
- PDF via `UIGraphicsPDFRenderer` or `PDFKit`.
- Filename: `underpaint-kit-<reference-name>-<date>.pdf`.

### 2.3 UI surface

- Replace the plain `Export` button with a menu: *Current view · Prep Sheet (PDF) · Prep Sheet (PNG)*. The current-view flow stays 1-tap for the field-painter (Persona B) use case.
- Progress UI during prep-sheet render (it may take 3-5s on older hardware — Value + Color reprocesses if not cached).

### 2.4 Caching

The prep sheet needs the value render and color render simultaneously. Today only one is in memory at a time because changing modes discards the other. Either:

- **Option A**: cache the last N mode renders keyed by `(mode, config, source hash)`. Memory cost ~4× a full-res UIImage per cached mode.
- **Option B**: re-process on demand during export (simpler, slower).

**Decision: Option B for v1.** Prep-sheet export is not frequent enough to justify holding ~40MB of cached bitmaps on a loaded device. Revisit after telemetry if people complain. (No telemetry is planned — use App Store reviews / support email.)

### Files touched

- New: `ios/RefPlane/Processing/PrepSheetRenderer.swift`
- New: `ios/RefPlane/Views/PrepSheetLayoutView.swift` (SwiftUI view used as render source)
- `ios/RefPlane/Models/AppState+Export.swift` — add prep-sheet export path
- `ios/RefPlane/Views/ContentView.swift` — export menu replaces button

### Acceptance

- Prep Sheet PDF exports from a loaded image in ≤ 10s on iPhone 13 (reference hardware).
- Output is page-sized (Letter or A4), print-quality, with all 4 panels rendered correctly.
- Recipe text is legible at 100% zoom in Preview.app.
- Grid overlay renders proportionally at page size.

### Risks

- Memory pressure when compositing large images. Mitigation: fixed page-size rendering, no full-source-resolution caching.
- Text legibility in the recipe block. Mitigation: typographic pass before shipping, test at 8pt and 10pt.

---

## Workstream 3 — Painter's Kit, Phase 2: Sessions & Palettes

### Goal

Turn the app from stateless-per-launch into one that remembers what painters have been working on and what paints they actually own.

### 3.1 Session history

**Problem:** Loading a new image destroys the previous session's analysis. The Studio Painter persona works from one reference across multiple painting sittings; re-picking the image and re-configuring every setting is friction they feel every session.

**Decision: on-device session history of the last 10 references.**

- Each session stores: reference image (full-res), `TransformationSnapshot`, depth mode, overlays, generated prep sheet (if any).
- Storage: `FileManager.default.urls(for: .applicationSupportDirectory)` + SQLite or a flat JSON index. **Flat JSON**, sessions directory: simpler, no schema migrations.
- UI: a "Recent" section in the image picker flow, next to "Samples". Tap a session to restore it exactly.
- Delete on swipe; "Clear history" button in About/Privacy sheet.
- Total disk cap: 500MB; oldest sessions evicted when exceeded.

**Privacy boundary:** this is user data stored on device. The "nothing leaves your phone" promise holds. Document in About/Privacy screen.

### 3.2 Named custom palettes

**Problem:** `ColorConfig.paletteSelectionEnabled` + pigment preset picker works for preset palettes (Zorn, Primary, Warm, Cool, All), but a painter who wants *their* palette — say, the 12 tubes actually on their taboret — has to re-select every time.

**Decision: "My Palettes" as a first-class concept.**

- Save named tube-subset: `Palette { name: "Taboret", pigmentIDs: Set<String> }`.
- UI: in the Palette Selection section, a menu with presets + saved custom palettes + "Save current as…".
- Storage: JSON in `Application Support`.
- Default set of examples: "Studio (12)", "Plein Air (6)", "Watercolor Classic (8)" — curated picks to demo the feature.

### 3.3 Expanded sample library

**Problem:** Samples are both the pre-purchase try-before-buy surface *and* the first-run tutorial surface, but the library has only a handful of images.

**Decision: ship 10-12 curated samples, organized into a grid with category labels.**

Categories:
- Portraits (3) — drive depth + value workflow
- Landscapes (3) — drive color + recipes
- Still life (3) — drive simplify + value
- Spatial photos (2-3) — drive the "shoot in Spatial" tip

Ensure licensing: all samples are either our own photographs or CC-BY with attribution in the About sheet.

### Files touched

- New: `ios/RefPlane/Models/SessionStore.swift`
- New: `ios/RefPlane/Models/CustomPaletteStore.swift`
- New: `ios/RefPlane/Views/SessionHistoryView.swift`
- `ios/RefPlane/Views/SampleImagePickerView.swift` — category groupings
- `ios/RefPlane/Views/ControlPanelView.swift` — palette save/load UI
- Samples: `ios/RefPlane/Assets.xcassets/` + attribution in `AboutPrivacyView.swift`

### Acceptance

- Loading a reference, switching mode, closing the app, reopening → "Recent" shows the reference; tapping it restores exact state.
- Saving "Taboret" with 12 selected tubes, switching palette, switching back → 12 tubes re-apply.
- Sample library shows 10+ curated references grouped by category.

### Risks

- Disk bloat from full-res images × 10 sessions. Mitigation: 500MB cap + evict-oldest.
- Restoring a session must not accidentally trigger processing on launch (battery / perceived lag). Mitigation: defer processing until user interacts with the restored session.

---

## Workstream 4 — Native Feel

### Goal

Polish. Make the app feel like a first-party Apple tool.

### 4.1 iOS 18 `Inspector` migration

Current: custom `ControlPanelView` + `drawer` / `sidebar` layout switch via `GeometryReader`.

**Decision: migrate to SwiftUI's `Inspector` with bottom-sheet detents.**

- `inspector(isPresented:)` handles iPad sidebar natively.
- `.inspectorColumnWidth` for sidebar sizing.
- Bottom-sheet on iPhone uses `.presentationDetents([.medium, .large])` on a `.sheet` — but only if the compact-while-dragging-sliders behavior can be preserved. Test first; fall back to current drawer if it regresses.

Prototype before committing — iOS 18 `Inspector` has known layout quirks.

### 4.2 Drag-and-drop image import

- `.dropDestination(for: Image.self)` on the canvas.
- `.dropDestination(for: URL.self)` for image files (Mac Catalyst especially).
- Replace the "Choose Photo" button from a tap to a tap-or-drop surface.

### 4.3 Mac Catalyst polish

- Menu bar commands: File → Open…, File → Save Prep Sheet…, View → Zoom In/Out/Reset, View → Original/Tonal/Value/Color, View → Compare.
- Keyboard shortcuts: `⌘1/2/3/4` for modes, `⌘=/⌘-/⌘0` for zoom, `⌘E` for export, `⌘⇧E` for prep sheet, `⌘C` for compare toggle, `⌘N` for Library.
- Cursor: hand cursor over draggable regions (compare slider, pan).
- `fileExporter` already branches on Catalyst ✓ — just verify the document type identifiers.

### 4.4 Accessibility pass

- VoiceOver walkthrough of scenarios 1, 2, 6.
- Dynamic Type stress test at `.accessibility3` and `.accessibility5`.
- Reduce Motion respected — already honored in several places; audit the rest.
- Contrast check on recipe text over ultraThinMaterial backgrounds.

### 4.5 TipKit audit

Current TipKit usage is good but some tips may be dated after workstream 1's rewrites (e.g., `PresetsTip` / `PaletteSelectionTip` phrasing). Re-review every registered tip after workstreams 1-3 land.

### Files touched

- `ios/RefPlane/Views/ContentView.swift` — Inspector migration
- `ios/RefPlane/RefPlaneApp.swift` — menu bar + keyboard shortcuts
- `ios/RefPlane/Views/ImageCanvasView.swift` — drop destination
- `ios/RefPlane/Support/AppTips.swift` — tip re-review

### Acceptance

- App passes a manual VoiceOver walkthrough of the first-value-study scenario without dead-ends.
- `⌘E` exports on Mac; `⌘1-4` switch modes.
- Drag-and-drop an image from Finder / Photos onto canvas loads the reference.
- iPad landscape with Inspector feels native (no layout jank on rotation).

### Risks

- iOS 18 `Inspector` regressions. Mitigation: keep current layout behind a feature flag for one release; fall back if bugs.

---

## Cross-cutting concerns

### Testing

Existing regression test suite (`docs/plans/2026-03-26-regression-test-suite-design.md`) covers processing correctness. Additions needed:

- `PrepSheetRendererTests` — layout sanity, PDF produces a non-empty page, values render at expected coordinates.
- `SessionStoreTests` — round-trip serialization, eviction at cap.
- `CustomPaletteStoreTests` — round-trip, duplicate-name handling.
- UX rubric re-score after workstream 1 and workstream 2.

### Performance budgets

- Cold launch to empty state: < 800ms on iPhone 13.
- Sample load + first mode switch: < 2s.
- Prep Sheet export: < 10s.
- Session restore: < 1.5s to visible image.

### Migration concerns

None — pre-launch, no user data in the wild. One exception: if internal TestFlight users have saved transform presets, plan a one-shot migration to the new mode naming. Low effort; mention in PR that lands workstream 1.

---

## Out of scope (for this plan)

Explicitly deferred:

- Additional study modes (line art, edge detection, Notan) — scope creep.
- Cloud sync / accounts — breaks the privacy positioning.
- Additional pigment brands (Winsor, Schmincke, watercolor lines) — spectral data sourcing is its own project.
- Apple Pencil / canvas drawing — would reposition the app.
- Localization beyond English — worth doing, but after launch stabilizes.
- Telemetry / analytics — conflicts with the privacy story; fall back to App Store reviews and support email.

---

## Sequencing & effort

Rough T-shirt sizing. Day = one focused working day.

| Workstream | Effort | Dependencies |
|------------|--------|--------------|
| 0. Foundations | 3-4d | none |
| 1. Clarity | 5-7d | 0 |
| 2. Prep Sheet | 4-6d | 0, 1 |
| 3. Sessions + Palettes | 4-5d | 2 (session stores prep sheet) |
| 4. Native feel | 3-4d | 1 |

**Total: 19-26 focused days.** Landing 0-2 is the minimum bar for a confident 1.0. 3-4 can trail into a 1.1 if needed.

---

## Open questions

1. **Is _Underpaint_ the final ship name?** Audit is cheap; renaming twice is not.
2. **Are we willing to add PDFKit as a dependency** for prep-sheet export, or should we stick with `UIGraphicsPDFRenderer` for zero new dependencies? (The latter is adequate; the former is more flexible if we ever want multi-page prep sheets.)
3. **Paywall hero screenshots** — do we have App Store-quality captures already, or does workstream 1.5 need a photography/rendering pass?
4. **Session storage format** — flat JSON per session (proposed) or a single index file? Flat-per-session is more resilient to corruption.
5. **Mac Catalyst priority** — is this a first-class target for 1.0, or "runs on Mac" as a bonus? Affects how much menu/keyboard work is in scope.
