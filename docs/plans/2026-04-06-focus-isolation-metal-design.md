# Focus Isolation Metal Design

## Goal

Make swatch focus feel immediate on large images and make the canvas Focus control visually match the sidebar control.

## Scope

- Move band-isolation rendering off the main actor.
- Add a Metal compute path for band isolation with the existing CPU implementation kept as fallback.
- Reuse one shared Focus pill view for both the palette sidebar and the canvas callout.
- Preserve the existing focus behavior and public AppState API.

## Design

- `BandIsolationRenderer` remains the single rendering entry point, but it now:
  - offers an async wrapper that performs image decode and render work away from the main actor;
  - tries a new Metal compute kernel first;
  - falls back to the current CPU math if Metal is unavailable.
- `MetalContext` gains a dedicated band-isolation pipeline that:
  - reads the processed RGBA pixel buffer;
  - checks each pixel band against the selected band list;
  - leaves selected pixels unchanged;
  - desaturates and dims non-selected pixels with the same formula used today.
- `AppState.refreshIsolatedProcessedImage()` becomes task-based and generation-guarded so stale focus results cannot overwrite newer selections after mode, image, or processing changes.
- The canvas callout stops using a custom narrow button style and instead renders the same shared Focus pill used by the palette sidebar, including one-line sizing to prevent the current vertical letter wrapping.

## Validation

- Keep the existing band-isolation rendering tests passing.
- Add regression coverage for multi-band and custom-parameter isolation through the shared renderer.
- Run the focused band-isolation tests and a simulator debug build.