# Underpaint Rebrand & HIG Compliance Plan

**Date:** 2026-03-26
**Status:** Canonical plan
**Canonical Path:** `docs/plans/2026-03-26-hig-compliance-design.md`

This document replaces the earlier split between a product-level HIG design note and a separate implementation plan. It is the single source of truth for the `Underpaint` rebrand and the iOS polish pass.

## 1. Overview

The current app works, but it still presents itself like an internal image-processing utility:

- the app shell is a custom panel-first layout instead of a native iOS editor
- the UI is globally forced into dark mode
- several labels expose implementation details instead of painter-facing language
- custom chrome, section headers, and button styles create a "developer UI" feel

The goal of this pass is to reposition `RefPlane` as `Underpaint`, a polished iOS reference-prep tool for painters and illustrators.

## 2. Goals

- Rename the app to `Underpaint` everywhere the user sees it.
- Make the app feel native on iPhone and iPad.
- Reduce the "developer UI" feel through simpler layout, calmer surfaces, and better copy.
- Keep the image-first workflow fast: open, study, adjust, compare, export.
- Adopt Apple HIG conventions for color, typography, controls, feedback, spacing, and accessibility.

## 3. Non-Goals

- Do not change the image-processing algorithms as part of this pass.
- Do not rename internal Swift types, target names, or folders unless needed for user-facing behavior.
- Do not lighten the image canvas itself; media surfaces should remain dark and content-first.

## 4. Current UX Findings

Grounded in the current SwiftUI implementation:

- `ContentView` uses a custom bottom panel in portrait and a custom collapsible inspector rail in landscape.
- `ControlPanelView` uses a hand-built stack of collapsible sections, hardcoded spacing, and utility-style headers.
- `ActionBarView` and `ModeBarView` reimplement common system controls instead of using native patterns.
- `RefPlaneApp` forces dark mode globally even though only the media canvas needs it.
- Simplification UI exposes technical implementation detail.
- Error feedback is handled through a custom toast rather than the default iOS presentation patterns.

## 5. Product Direction

`Underpaint` should feel like a focused studio tool, not a technical console.

The UI should emphasize:

- the reference image first
- a small number of clear study modes
- progressive disclosure for advanced controls
- native iOS controls and grouped surfaces
- plain-language copy that supports art-making rather than implementation detail

## 6. Rebrand Scope

### Required user-facing rename

The following should change from `RefPlane` to `Underpaint`:

- app display name
- visible in-app title
- photo-library permission copy
- README and product-facing docs
- any future user-visible export/share labels or metadata

### Internal rename policy

For this pass, internal names may remain `RefPlane` where changing them would add risk without improving the shipped product:

- Xcode target name
- scheme name
- Swift types such as `RefPlaneApp` and `RefPlaneMode`
- repo folder names

### Optional follow-up

If distribution strategy allows it, a later cleanup pass may rename:

- target and scheme
- product name
- bundle identifier
- top-level iOS folder names

That should be a separate decision because it affects app identity and continuity.

## 7. UX And Visual Direction

### 7.1 App shell

The app should remain a single-scene editor, but the shell should feel native.

**iPhone portrait**

- keep the canvas as the primary surface
- move controls into a bottom sheet with medium and large detents
- use a top toolbar for import, compare, export, and inspector actions

This replaces the custom half-height bottom panel.

**iPad and wide landscape**

- keep the canvas and inspector visible together
- use a clean trailing inspector surface around 320-360pt wide
- show or hide the inspector from a normal toolbar action, not a thin chevron strip

### 7.2 Information architecture

The inspector should be organized in this order:

1. `Mode`
2. `Simplify`
3. `Adjustments`
4. `Palette`
5. `Grid`

Rules:

- show only sections relevant to the selected mode
- keep common controls near the top
- avoid nested custom collapsible subsections
- hide low-value technical detail unless there is a clear user-facing need

### 7.3 Mode labels

Recommended user-facing labels:

- `Original`
- `Tonal`
- `Value`
- `Color`

`Source` is acceptable if the team prefers it, but the language should stay art-study oriented.

### 7.4 Simplify section

The simplify UI should present user intent first:

- `Simplify Image` toggle
- `Strength` slider

Only surface a method picker when there is more than one shippable option. If multiple methods are exposed later, do not show raw model identifiers such as `APISR`; use user-facing names.

### 7.5 Visual system

Outside of media surfaces, use semantic system colors and materials.

| Current pattern | New direction |
|------|------|
| hardcoded grayscale backgrounds | `systemBackground`, `secondarySystemGroupedBackground`, `systemGroupedBackground` |
| hardcoded white text opacity stacks | `.primary`, `.secondary`, `.tertiary`, `.quaternary` |
| custom translucent fills | `secondarySystemFill`, `tertiarySystemFill`, system materials |
| custom divider colors | native `Divider` and `Section` separators |

The canvas and compare surfaces remain black or near-black regardless of appearance mode.

### 7.6 Typography

Use semantic text styles and Dynamic Type:

- titles: `title3` or `headline`
- section headers: standard `Section` headers or `footnote.weight(.semibold)`
- values: `subheadline.monospacedDigit()`
- helper text: `footnote` or `caption`

Avoid all-caps utility styling unless it adds meaningful hierarchy.

### 7.7 Feedback

- empty states should use one clear primary action and supportive text
- processing states should use `ProgressView` with plain-language labels
- blocking processing and loading failures should default to `alert`
- banner-style surfaces are only appropriate for transient, non-blocking notices

### 7.8 Accessibility

- all controls meet the 44pt minimum touch target
- all labels use semantic text styles
- compare slider exposes value and adjustability
- palette selection exposes selected state
- reduce-motion mode disables spring-heavy transitions
- both light and dark appearance preserve contrast on non-canvas surfaces

## 8. Copy And Terminology

The app should sound like a creative tool, not a pipeline debugger.

Recommended copy changes:

- `RefPlane` -> `Underpaint`
- `Show Panel` -> `Adjustments`
- `Enable Simplification` -> `Simplify Image`
- raw method names such as `APISR` -> hidden or replaced with user-facing names
- `Tap to open an image` -> `Choose a reference image`

Recommended photo-library permission copy:

`Underpaint needs access to your photo library so you can choose reference images for study and painting.`

## 9. File Map

All work stays within existing files.

| File | Responsibility in this plan |
|------|------|
| `ios/RefPlane/RefPlaneApp.swift` | remove forced global dark mode |
| `ios/RefPlane/Views/ContentView.swift` | native app-shell behavior, inspector presentation, error presentation |
| `ios/RefPlane/Views/ControlPanelView.swift` | convert custom panel chrome into native grouped inspector content |
| `ios/RefPlane/Views/ActionBarView.swift` | move toward toolbar-native controls and title treatment |
| `ios/RefPlane/Views/ModeBarView.swift` | replace custom segmented control with native segmented picker |
| `ios/RefPlane/Views/ThresholdSliderView.swift` | semantic colors and control polish for reusable setting rows |
| `ios/RefPlane/Views/GridSettingsView.swift` | adapt settings to native `Form` usage |
| `ios/RefPlane/Views/ValueSettingsView.swift` | adapt settings to native `Form` usage and simplify copy |
| `ios/RefPlane/Views/ColorSettingsView.swift` | adapt settings to native `Form` usage |
| `ios/RefPlane/Views/PaletteView.swift` | improve selection clarity, touch targets, and semantic styling |
| `ios/RefPlane/Views/ImageCanvasView.swift` | keep dark media surface, upgrade overlays, improve empty state |
| `ios/RefPlane/Views/CompareView.swift` | polish compare labels and handle while keeping dark media surface |
| `ios/RefPlane/Views/ErrorToastView.swift` | either restyle for non-blocking use or retire in favor of alerts |
| `ios/RefPlane.xcodeproj/project.pbxproj` | update display name and permission string |
| `README.md` | update product-facing naming and terminology |

## 10. Execution Plan

This should ship in phases rather than as one monolithic rewrite.

### Phase 1: Foundation And Rebrand

**Primary files**

- `ios/RefPlane/RefPlaneApp.swift`
- `ios/RefPlane/Views/ImageCanvasView.swift`
- `ios/RefPlane/Views/CompareView.swift`
- `ios/RefPlane.xcodeproj/project.pbxproj`
- `README.md`

**Work**

- remove `.preferredColorScheme(.dark)` from the app entry point
- keep the image canvas and compare views pinned to dark appearance
- set `CFBundleDisplayName` to `Underpaint`
- update the photo-library permission copy to the new user-facing wording
- rename visible product references in docs and UI copy

**Result**

- the app can participate in system light and dark mode correctly
- only media surfaces stay dark by design
- users see `Underpaint` consistently

### Phase 2: App Shell Modernization

**Primary files**

- `ios/RefPlane/Views/ContentView.swift`
- `ios/RefPlane/Views/ControlPanelView.swift`
- `ios/RefPlane/Views/ActionBarView.swift`

**Work**

- replace the portrait custom panel with a bottom inspector sheet using detents
- replace the wide-layout chevron rail with a cleaner inspector show-hide affordance
- use a normal toolbar/title treatment rather than embedding identity into a custom dark header
- preserve compare and export actions, but present them using native button and toolbar patterns

**Result**

- the app stops feeling like a desktop tool wrapped in SwiftUI
- iPhone portrait becomes substantially more native

### Phase 3: Inspector And Controls Cleanup

**Primary files**

- `ios/RefPlane/Views/ControlPanelView.swift`
- `ios/RefPlane/Views/ModeBarView.swift`
- `ios/RefPlane/Views/ThresholdSliderView.swift`
- `ios/RefPlane/Views/GridSettingsView.swift`
- `ios/RefPlane/Views/ValueSettingsView.swift`
- `ios/RefPlane/Views/ColorSettingsView.swift`
- `ios/RefPlane/Views/PaletteView.swift`

**Work**

- replace custom panel sections with `Form` and `Section`
- replace the custom mode bar with a native segmented picker
- switch reusable controls to semantic colors and typography
- remove manual tint hacks and hardcoded white-on-dark styling from settings views
- make palette rows large enough to read as selectable, not incidental
- simplify copy so the inspector reads like a creative tool

**Result**

- the inspector uses native grouped patterns
- settings read clearly in both light and dark appearance
- control density and terminology improve substantially

### Phase 4: Feedback, Overlays, And Accessibility

**Primary files**

- `ios/RefPlane/Views/ContentView.swift`
- `ios/RefPlane/Views/ImageCanvasView.swift`
- `ios/RefPlane/Views/CompareView.swift`
- `ios/RefPlane/Views/ErrorToastView.swift`

**Work**

- update processing overlays to use materials and clearer progress copy
- replace toast-first error handling with alerts for blocking failures
- add VoiceOver labels, values, traits, and hints where missing
- enforce 44pt touch targets for collapse, palette, and dismiss interactions
- respect Reduce Motion when transitioning inspector surfaces

**Result**

- the app feels more native under load and in failure states
- accessibility is built into the surface rather than patched later

### Phase 5: Verification And Cleanup

**Work**

- build the app after each phase with `xcodebuild`
- verify portrait and landscape on iPhone plus wide layout on iPad
- verify light mode and dark mode separately
- verify compare flow, export flow, empty state, and image reload flow
- scan for remaining hardcoded dark-only styling in view code
- confirm no user-visible `RefPlane` strings remain in the shipped app surface

## 11. Implementation Checklist

This checklist replaces the old long-form task script.

- [ ] Remove forced dark mode from `RefPlaneApp.swift`
- [ ] Keep `ImageCanvasView` and compare views dark regardless of system appearance
- [ ] Update `project.pbxproj` with `Underpaint` display name and revised photo permission string
- [ ] Update product-facing copy in `README.md`
- [ ] Rework `ContentView` so portrait uses a native inspector sheet
- [ ] Rework wide layouts so inspector visibility is controlled with normal app chrome
- [ ] Convert `ControlPanelView` to a native grouped inspector structure
- [ ] Replace `ModeBarView` with a native segmented picker
- [ ] Update `ThresholdSliderView` and other reusable controls to use semantic colors
- [ ] Adapt `GridSettingsView`, `ValueSettingsView`, and `ColorSettingsView` to `Form` rows
- [ ] Improve `PaletteView` touch targets and selection feedback
- [ ] Update canvas and compare overlays to use material-backed surfaces where appropriate
- [ ] Replace blocking error toast behavior with alerts
- [ ] Add accessibility labels, values, traits, and reduce-motion behavior
- [ ] Verify the app in light mode, dark mode, portrait, landscape, and compare workflows

## 12. Acceptance Criteria

The work is complete when all of the following are true:

- the shipped app is called `Underpaint` everywhere the user sees it
- the app no longer looks broken or improvised in light mode
- iPhone portrait no longer relies on a custom half-height control drawer
- the control surface reads as an inspector for artists rather than a developer tool panel
- no raw model identifiers are exposed in the default user flow
- non-media UI uses semantic colors, Dynamic Type, and native control styling
- errors and progress feedback follow standard iOS patterns

## 13. Notes On Scope

The earlier implementation plan optimized for incremental edits inside the current structure. This merged plan keeps its useful file map and execution breakdown, but changes the target where necessary:

- portrait should move to a sheet-based inspector instead of preserving the current custom panel
- rebranding is broader than the app icon label
- error handling should move closer to standard iOS patterns rather than just restyling the existing toast

## 14. Summary Decision

The correct path is not to merely restyle the current dark utility panel. `Underpaint` should keep the existing fast single-screen workflow, but the shell, copy, and inspector behavior need to shift toward native iOS patterns. This plan defines both the product direction and the concrete file-by-file work needed to get there.
