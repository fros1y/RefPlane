# Skill Observation Log

Observations captured during task-oriented work. Each entry identifies a
potential skill improvement or new skill opportunity.

**Status key:** OPEN = not yet actioned | ACTIONED = skill updated/created |
DECLINED = user decided not to pursue

---

## 2026-04-03

### Observation 1: Use PTY-backed xcodebuild runs for simulator XCTest
**Status:** OPEN

**Date:** 2026-04-03
**Session context:** Iteratively improving a SwiftUI iOS app UI and adding screenshot-capture UI tests on iPhone and iPad simulators.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** Simulator test execution and result collection

**Issue:** `xcodebuild test` launched through plain pipe output repeatedly appeared to hang after tests completed, leaving incomplete teardown state and delaying access to xcresult diagnostics. Re-running the same command with `tty=true` exited cleanly and made simulator test loops reliable.

**Suggested improvement:** Add a PTY-backed XCTest execution rule to the simulator debugging skill or local workflow notes for this workspace: prefer `exec_command` with `tty=true` for `xcodebuild test`, then inspect failures through `xcresulttool` instead of relying on raw terminal output.

**Principle:** When a toolchain command has different process-lifecycle behavior under pseudo-TTY vs plain pipes, encode the execution mode in the workflow itself so verification loops remain deterministic.

### Observation 2: Tap the trailing edge of labeled SwiftUI switches in XCUITest
**Status:** OPEN

**Date:** 2026-04-03
**Session context:** Reworked the RefPlane processing panel into a simpler pipeline and updated screenshot-driving UI tests for iPhone and iPad.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** UI test interaction with SwiftUI forms

**Issue:** `switch.tap()` on a wide labeled SwiftUI `Toggle` could hit the label area instead of the thumb, leaving the control unchanged even though the accessibility element existed and was hittable.

**Suggested improvement:** When driving labeled toggles in XCUITest, tap a trailing-edge coordinate inside the switch element and then assert the `value` changed to `1` or `0`. If a toggle appears to no-op, inspect the accessibility attachment to verify whether the element frame includes both label and thumb.

**Principle:** For UI automation, validate state after every control action and bias taps toward the actual interactive affordance when an accessibility element's frame spans non-interactive label content.

### Observation 3: Keep inspector cards action-named and make optional pipeline stages explicit
**Status:** OPEN

**Date:** 2026-04-03
**Session context:** Simplified a SwiftUI image-processing inspector after user feedback that numbered sections and explanatory subtitles made the panel feel cluttered and that quantization should not imply palette fitting.
**Skill:** build-ios-apps:swiftui-ui-patterns
**Type:** internal
**Phase/Area:** Inspector IA, labels, and feature toggles

**Issue:** Numbered section titles plus per-card helper copy made the panel read like documentation instead of controls, and bundling pigment palette fitting into the Quantize stage hid a distinct optional processing step.

**Suggested improvement:** For settings inspectors, use short action-oriented card titles without numeric prefixes, avoid descriptive subtitles unless a control is unavailable, and represent optional downstream processing stages with a dedicated default-off toggle and independent state flag.

**Principle:** In dense tool UIs, reduce copy before adding layout complexity, and model conceptually separate pipeline stages as separate state so the interface matches the mental model.

### Observation 4: Collapse overlay panels before asserting canvas tap side effects
**Status:** OPEN

**Date:** 2026-04-03
**Session context:** Added tap-to-swatch behavior on the image canvas while iterating a bottom-drawer inspector on iPhone and a sidebar inspector on iPad.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** UI automation for canvas gestures under overlapping inspector chrome

**Issue:** A screenshot test tapped the canvas while the phone drawer covered nearly the entire image, so the band-callout assertion failed even though the feature worked when the inspector was hidden.

**Suggested improvement:** When validating direct canvas gestures, collapse overlapping inspectors first, tap a visible center-region point, then reopen the controls panel for follow-on assertions. For SwiftUI gesture stacks, prefer a high-priority `SpatialTapGesture` with an explicit `contentShape` when taps must coexist with pan/zoom gestures.

**Principle:** UI tests should interact with the same visible affordances a user sees; if an overlay occludes a target, verify gesture behavior in the unobstructed layout state.

## 2026-04-04

### Observation 5: Trust the newest xcresult bundle before a stale xcodebuild shell
**Status:** OPEN

**Date:** 2026-04-04
**Session context:** Replaced a discrete SwiftUI quantization-bias picker with a continuous slider and verified the iPad screenshot test.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** XCTest result verification and process teardown

**Issue:** The iPad `xcodebuild test` parent process stayed alive with no active test-runner child, but the newest `.xcresult` bundle already reported `status = succeeded` and an `endedTime`, indicating the test action had finished.

**Suggested improvement:** When `xcodebuild` appears idle after UI tests, inspect the newest `/tmp/.../Logs/Test/*.xcresult` with `xcrun xcresulttool get --legacy --format json` before rerunning tests. If the bundle is succeeded and has an `endedTime`, treat the run as complete and clean up only the stale shell process.

**Principle:** Separate test outcome from shell-process liveness; `.xcresult` is the authoritative artifact when terminal lifecycle and simulator teardown drift apart.

### Observation 6: Guard zero-candidate fast paths before remapping palette labels
**Status:** OPEN

**Date:** 2026-04-04
**Session context:** Fixed a crash when palette selection used a single custom tube and updated grayscale/palette UI controls.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** Palette decomposition edge cases and regression coverage

**Issue:** The precomputed pigment lookup fast path only searched pair/triplet mixes, so a one-pigment selection returned no recipes. A later merge-map projection then indexed an empty array and crashed with `Fatal error: Index out of range`.

**Suggested improvement:** Add explicit single-item fast paths for combinatorial search tables, and add hard guards at every downstream remap/prune boundary that can receive an empty candidate set. Pair that with a one-choice regression test for user-editable subsets.

**Principle:** If upstream search cardinality can collapse to 0 or 1, encode those cases directly and verify downstream code never assumes a non-empty survivor set.

### Observation 7: Preserve image metadata at the byte boundary, not after UIImage decoding
**Status:** OPEN

**Date:** 2026-04-04
**Session context:** Added metadata-preserving image import/export and a git-revision provenance stamp to processed RefPlane exports.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** Image pipeline IO and export provenance

**Issue:** Loading photo-library selections as `UIImage` and exporting processed results with `pngData()` stripped source metadata and left no stable provenance record for the settings/build that produced an exported image.

**Suggested improvement:** Capture ImageIO properties from picker byte data before decoding, keep that snapshot in app state, and write exports through `CGImageDestination` with a merged metadata dictionary plus app-specific provenance JSON. For build identity, generate a dedicated bundle resource in an Xcode run script instead of editing `Info.plist` in place.

**Principle:** Metadata survives reliably when captured and rewritten at file-encoding boundaries; once an image is reduced to `UIImage`, provenance must be carried in parallel state.

### Observation 8: Scale planning gates to change scope
**Status:** OPEN

**Date:** 2026-04-04
**Session context:** Added a one-tap “Copy Settings” action to the About sheet and backed it with a shared plain-text formatter from `AppState`.
**Skill:** brainstorming
**Type:** open-source
**Phase/Area:** Lightweight implementation requests with known local context

**Issue:** The brainstorming skill’s hard “design then approval” gate is too heavy for a narrow, clearly scoped UI addition in an already-understood codebase, and conflicts with a user workflow that expects direct implementation plus verification.

**Suggested improvement:** Allow a fast path for bounded one-screen or one-function changes: state a one-paragraph design inline, proceed with implementation, and reserve explicit approval gates for broad UX, architecture, or product-behavior decisions.

**Principle:** Planning rigor should scale with blast radius; a mandatory stop-the-world design gate can be counterproductive for small, reversible edits with obvious acceptance criteria.

### Observation 9: Inject Observation environment explicitly into modal sheets
**Status:** OPEN

**Date:** 2026-04-04
**Session context:** Fixed a crash when presenting the About sheet after adding `@Environment(AppState.self)` to `AboutPrivacyView`.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** SwiftUI sheet presentation and Observation environment propagation

**Issue:** `AboutPrivacyView` read `@Environment(AppState.self)`, but the sheet presentation path instantiated the view without explicitly attaching `.environment(state)`, causing a fatal runtime crash when the sheet opened.

**Suggested improvement:** For every sheet/popover/full-screen modal whose content reads a custom Observation environment object, attach the object explicitly at the modal content root and verify by opening the modal in a simulator smoke test.

**Principle:** Don’t rely on implicit environment propagation across presentation boundaries for app-critical state; make modal dependencies explicit and exercise the presentation path in UI verification.

### Observation 10: Reproduce solver regressions in suite order and print stage snapshots
**Status:** OPEN

**Date:** 2026-04-04
**Session context:** Fixed a Still Life palette-collapse bug where APISR-simplified lime regions lost their green pigment recipe only during the full `PaintPaletteBuilderTests` suite, not in isolated test runs.
**Skill:** build-ios-apps:ios-debugger-agent
**Type:** internal
**Phase/Area:** Algorithmic regression tests and failure localization

**Issue:** The failing behavior appeared only after earlier tests ran first, and the final symptom (“no green recipe in the output palette”) didn’t reveal whether quantization, direct pigment decomposition, snap/refit, or pruning dropped the green cluster.

**Suggested improvement:** Always rerun image/solver regressions in full-suite order after an isolated pass. When final-output assertions fail, add staged diagnostics for the source centroid, one-shot decomposition, batch decomposition, first assignment, and first refit so the failure message identifies the exact stage that loses the signal.

**Principle:** For multi-stage optimization pipelines, encode stage snapshots into regression failures; a final output diff alone is usually too late to identify where a small but perceptually important feature was discarded.
