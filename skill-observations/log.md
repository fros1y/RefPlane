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
