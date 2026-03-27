# Regression Test Suite Design

## Goal

Add a native Xcode test target that can lock down the current regression-prone behavior in `RefPlane` before broader remediation work.

## Scope

The first pass of the suite focuses on the four highest-value areas from review:

1. Grid auto-contrast behavior.
2. Simplify task cancellation and stale completion suppression.
3. Palette-band grouping and future isolation contracts.
4. Export contracts around original-image fidelity.

## Approach

- Add a `RefPlaneTests` unit test target to the existing Xcode project.
- Use Apple's `Testing` framework for the runner and assertions.
- Use a small deterministic in-repo property-test harness for pure logic so the suite stays self-contained.
- Extract small helpers from UI code so we can test invariants without spinning up full SwiftUI views.
- Add dependency-injection seams to `AppState` so task lifecycle can be tested without invoking Metal/CoreML.

## Test Categories

### Property-based

- Threshold sanitization remains bounded, sized, ordered, and idempotent.
- Palette-band grouping preserves section order and index membership.
- Auto-contrast grid selection always picks the stronger of black/white contrast.

### Example-based

- Turning off simplify cancels in-flight simplify work.
- Exporting in original mode prefers the full-resolution source asset.

## Deliberate Non-Goals

- Full UI snapshot coverage.
- Simulator-driven UI tests.
- Full-resolution processed export rendering in this pass.
- Palette-isolation rendering itself in this pass.

Those need broader product and pipeline changes; the first suite establishes the support structure and executable contracts around the current hot spots.
