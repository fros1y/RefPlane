# UX Rubric Iteration and Screenshot Capture Design

**Date:** 2026-04-03
**Status:** Approved implementation plan
**Canonical Path:** `docs/plans/2026-04-03-ux-rubric-iteration-and-screenshot-capture-design.md`

## Goal

Use `docs/ux-scenarios-and-rubrics.md` as the UI evaluation rubric, make a low-risk SwiftUI polish pass that improves first-use clarity and study-mode discoverability across iPad, iPhone, and desktop, and add repeatable screenshot capture for scenario review.

Priority order for tradeoffs:

1. iPad
2. iPhone
3. Desktop / Mac

## Recommended Approach

Keep the current single-scene canvas + inspector architecture, but improve the parts that directly map to the rubric:

- keep study modes visible outside hidden menus
- make mode labels readable, not icon-only
- improve palette and recipe scanning so the dominant pigment is obvious
- expose stable accessibility identifiers for canvas, chrome, inspector, and sample flows
- add a scenario-driven XCTest flow that captures named screenshots and writes standalone PNGs under `artifacts/ux-screenshots/`

## Why This Approach

This gives high rubric coverage with a limited behavioral blast radius. It avoids a full app-shell rewrite while still improving Scenario 1, 3, 4, 5, 6, and 8 and making future iterations measurable.

## Alternatives Considered

### Full inspector rewrite with native sheets/forms

Potentially stronger long-term HIG alignment, but larger regression risk around zoom, compare, and depth sliders.

### Screenshot infrastructure only

Lower implementation risk, but it does not address immediate discoverability and recipe-legibility gaps called out by the rubric.

## Implementation Plan

### UI polish

- Show the floating mode dock on wide layouts too, not only in the phone drawer layout.
- Replace icon-only mode buttons with compact icon + text labels.
- Add a persistent study-mode strip to the inspector when an image is loaded.
- Increase palette swatch size and make isolated mix cards more visually distinct.
- Make the dominant pigment row visually prominent and express recipe amounts as painter-friendly parts.
- Respect Reduce Motion for empty-state breathing animation.

### Screenshot automation

- Add accessibility identifiers for top chrome actions, inspector sections, mode controls, sample cards, compare slider, processing overlays, and canvas states.
- Extend the existing UI test target with a scenario walkthrough that uses bundled samples, waits for processing to settle, captures screenshots at key states, and saves PNG files to `artifacts/ux-screenshots/<device>/`.
- Keep standard `XCTAttachment` screenshots as well, so screenshots are visible in Xcode and CI result bundles.

### Validation

- Run the expanded UI test on at least one iPad simulator and one iPhone simulator when available.
- Confirm screenshots are written to `artifacts/ux-screenshots/`.
- Sanity-check that first-use, value study, compare, mixing, and depth screens remain usable after the visual changes.

