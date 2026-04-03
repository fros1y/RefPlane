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
