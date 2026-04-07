# Canvas Second-Tap Focus Design

## Goal

Make canvas band selection a two-step interaction: first tap shows the info bubble, second quick tap on the same band enters focus.

## Scope

- Keep the first tap as an inspect action that shows the swatch bubble.
- Treat a second tap on the same band within a short window as a focus action.
- Preserve viewport reset, but only for repeated taps that do not resolve to a band.
- Keep palette swatch behavior unchanged.

## Design

- `ImageCanvasView` tracks the most recent canvas tap as `(band, timestamp)`.
- A first tap on a band returns `inspect(band)` and shows the info bubble.
- A second tap within the repeat window on that same band returns `focus(band)` and enables focus if it is not already active.
- Repeated taps on empty canvas return `resetViewport`, which preserves the old double-tap-to-reset affordance without conflicting with band focus.
- After a focus or reset action, the tap tracker clears so the next interaction starts a fresh cycle.

## Validation

- Add unit tests for inspect, focus, delayed repeat, and empty-canvas reset decisions.
- Run the focused interaction tests plus a simulator debug build.