# AppState Decomposition Design

## Objective

Refactor `AppState` so it no longer acts as a monolithic container for unrelated UI state, depth state, processing status, preset management, and formatter logic.

## Target Shape

`AppState` remains the single `@MainActor @Observable` coordinator exposed to SwiftUI. It continues to own cross-feature derived images and orchestration methods such as image loading, abstraction, processing, depth computation, and contour recomputation.

Feature-local mutable state moves into child observable objects owned by `AppState`:

- `TransformState`
  - `activeMode`
  - abstraction settings
  - grid, value, color, and contour configs
  - transform preset selection state
- `DepthState`
  - depth config
  - embedded and computed depth outputs
  - threshold preview state and Metal cache handles
  - contour segments derived from depth
- `PipelineState`
  - processing flags and labels
  - user-facing error state
  - compare mode and focus-isolation state
  - slider interaction state used by the panel layout

## AppState Responsibilities After Refactor

`AppState` keeps these responsibilities:

- source image ownership
- processed image ownership
- palette and recipe results
- coordination across transform, depth, and pipeline state
- derived display image selection
- export entry points

`AppState` should stop storing large groups of feature-local state directly.

## API Boundary

Views should migrate from broad root access like `state.gridConfig` or `state.isProcessing` to feature-specific access such as:

- `state.transform.gridConfig`
- `state.transform.valueConfig`
- `state.depth.depthConfig`
- `state.depth.depthRange`
- `state.pipeline.isProcessing`
- `state.pipeline.focusedBands`

The root object may keep a small number of derived convenience APIs where the value is genuinely cross-cutting, such as `currentDisplayImage`.

## Migration Plan

1. Introduce child observable state objects and make `AppState` own them.
2. Replace root stored properties with child-state access while keeping `AppState` orchestration intact.
3. Move preset-related logic into a dedicated AppState extension and operate on `TransformState`.
4. Move depth and contour logic into a dedicated AppState extension and operate on `DepthState` and `PipelineState`.
5. Update views and tests to bind to child state objects directly.
6. Extract formatter-heavy export and depth-diagnostic helpers so `AppState` no longer carries those long pure-logic sections inline.

## Constraints

- No dependency changes.
- Preserve structured task cancellation behavior.
- Preserve export behavior on the plain PNG path.
- Preserve focus isolation, depth preview, and contour behavior.
- Keep the refactor incremental enough to validate with targeted tests and a simulator build.

## Validation

- Update `AppState`-related tests to use child state paths where appropriate.
- Run targeted AppState tests.
- Run the Debug simulator build.