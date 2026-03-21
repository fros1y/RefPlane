# Comprehensive Test Suite Design

## Goal

Add a layered automated test suite for RefPlane that covers pure processing logic, stateful UI behavior, browser workflows, and visual regressions.

## Scope

- Add unit and component testing with Vitest.
- Add browser workflow and screenshot testing with Playwright.
- Add checked-in fixtures and golden outputs for image-processing regressions.
- Add test scripts and configuration for local development and CI use.

## Design

- Use Vitest as the primary fast runner for pure modules in `src/processing`, `src/compositing`, `src/color`, and selected UI components.
- Use `@testing-library/preact` with `jsdom` for component interaction tests around mode switching, overlays, crop/compare UI state, and palette behavior.
- Use Playwright for real browser flows: open image, switch modes, crop, compare, export trigger, overlay toggles, and mobile layout checks.
- Keep a small fixture library under `tests/fixtures` with representative source images:
  - a photographic reference
  - a flat-color / graphic image
  - a high-contrast line-heavy image
- Store stable golden outputs for processing modules under `tests/golden` and compare generated output buffers against them with bounded tolerance where appropriate.
- Store browser screenshot baselines for key desktop and mobile states and fail on unexpected visual drift.

## Initial Coverage Plan

- Unit:
  - grayscale conversion
  - edge generation
  - temperature mapping
  - compositing behaviors
  - threshold / isolation helpers
- Component:
  - mode bar selection
  - overlay toggles and settings panels
  - action bar behavior
  - compare and crop UI interactions
- Browser:
  - open image
  - mode transitions
  - grid / edges / temp overlays
  - crop flow
  - compare flow
  - desktop and mobile visual states

## Tradeoffs

- Browser and visual tests will be slower and more brittle than unit tests, so the suite is split into fast and slow layers.
- Golden outputs add repository weight, but they are the most direct protection against silent image-processing regressions.
- Some canvas-based assertions will need tolerance rather than exact byte-for-byte equality across environments.

## Verification

- `npm run test:unit` must pass locally without a browser.
- `npm run test:e2e` must pass against the local Vite app.
- `npm run test:visual` must pass against checked-in baselines.
- `npm run build` must continue to pass with the new test tooling present.
