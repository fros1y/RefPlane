# TipKit Integration Plan

**Date:** 2026-04-05
**Status:** Canonical plan
**Canonical Path:** `docs/plans/2026-04-05-tipkit-integration-design.md`

## 1. Overview

Add contextual in-app tips using Apple's TipKit framework to help new users discover RefPlane's non-obvious features. The app has significant hidden depth — simplification, background/depth effects, compare mode, presets, and export — that users won't find without guidance. TipKit provides frequency capping, eligibility rules, and persistence out of the box, eliminating the need for custom onboarding UI.

## 2. Goals

- Surface the app's most valuable features to first-time users.
- Use conservative pacing: one tip at a time, gated on having an image loaded, capped at daily frequency.
- Use popovers for toolbar/chrome buttons, banners for broader concepts in the control panel.
- Keep tips informational only — no action buttons.
- Integrate cleanly into existing views without restructuring.

## 3. Non-Goals

- No custom onboarding flow, walkthrough, or tutorial screens.
- No action buttons on tips (e.g., "Try it", "Open settings").
- No strict linear sequencing between tips — TipKit's eligibility system handles ordering naturally.
- No tips for basic operations (loading an image, switching modes) — only for features users might miss.

## 4. Design Decisions

### Pacing Strategy

- **Display frequency**: `.daily` — TipKit will show at most one tip per calendar day.
- **Max display count**: Each tip shows once (`MaxDisplayCount(1)`).
- **Gate event**: All tips require an `ImageLoadedEvent` to have been donated at least once. No tips appear until the user has loaded an image and had a moment to orient.
- **One at a time**: TipKit's default behavior — only one popover/inline tip is eligible at a time.

### Placement Rules

| Tip | Style | Anchor |
|-----|-------|--------|
| Simplification | Banner | Control panel, simplification section |
| Background/Depth | Banner | Control panel, background section |
| Compare Mode | Popover | Compare button in `StudioCanvasChrome` |
| Presets | Banner | Control panel, preset selector area |
| Export | Popover | Export button in `StudioCanvasChrome` |
| Palette Selection | Banner | Control panel, palette section |

### Tip Content

All tips are one sentence. They describe what the feature does for the user's painting workflow, not how to use the control.

| Tip ID | Title | Message |
|--------|-------|---------|
| `simplificationTip` | "Simplify Your Reference" | "Reduce detail to see the essential shapes and values — useful for blocking in." |
| `backgroundDepthTip` | "Separate Foreground & Background" | "Use AI depth estimation to blur, compress, or remove the background." |
| `compareModeTip` | "Compare Before & After" | "Slide to compare your original image with the current study." |
| `presetsTip` | "Save Your Settings" | "Save the current mode and settings as a preset you can reapply to any image." |
| `exportTip` | "Export Your Study" | "Export the processed image with overlays baked in." |
| `paletteSelectionTip` | "Match to Real Pigments" | "Enable palette selection to decompose colors into paintable pigment recipes." |

### Eligibility Rules

Each tip has two rules:

1. **Shared**: `ImageLoadedEvent` must have been donated (user has loaded at least one image).
2. **Contextual**: The tip's relevant UI must be visible. Popovers are self-gating (they're attached to visible buttons). Banners check that the control panel is open and the relevant section is present.

No tip references another tip's state — they are independently eligible. TipKit's daily frequency cap and one-at-a-time display handle pacing.

### Priority Ordering

TipKit evaluates eligible tips and shows the highest-priority one. We use the `options` parameter to set priority via `Tips.Priority`:

1. `.high` — Simplification, Background/Depth (most impactful features)
2. `.medium` — Compare Mode, Presets
3. `.low` — Export, Palette Selection (more niche)

## 5. Architecture

### New Files

| File | Purpose |
|------|---------|
| `ios/RefPlane/Support/AppTips.swift` | All tip definitions, the shared event, and TipKit configuration helper |

### Modified Files

| File | Change |
|------|--------|
| `RefPlaneApp.swift` | Call `Tips.configure()` at launch |
| `AppState.swift` | Donate `ImageLoadedEvent` when an image is set |
| `ContentView.swift` | Attach popover tips to compare and export buttons in `StudioCanvasChrome` |
| `ControlPanelView.swift` | Embed `TipView` banners in simplification, background, preset, and palette sections |

### Tip Definition Pattern

Each tip is a struct conforming to `Tip`:

```swift
struct SimplificationTip: Tip {
    static let imageLoaded = ImageLoadedEvent()

    var title: Text { Text("Simplify Your Reference") }
    var message: Text? { Text("Reduce detail to see the essential shapes and values — useful for blocking in.") }

    var options: [any TipOption] {
        [
            MaxDisplayCount(1),
            Tips.Priority(.high)
        ]
    }

    var rules: [any TipRule] {
        [
            #Rule(Self.imageLoaded) { $0.donations.count >= 1 }
        ]
    }
}
```

### Event Donation

In `AppState`, when `fullResolutionOriginalImage` is set (from photo library or sample selection):

```swift
ImageLoadedEvent().donate()
```

This is the single donation point. All tips share this event reference.

### TipKit Configuration

In `RefPlaneApp.init()` or as a `.task` modifier on the root view:

```swift
try? Tips.configure([
    .displayFrequency(.daily)
])
```

### View Integration

**Popovers** (toolbar buttons):

```swift
Button { /* compare action */ } label: { /* ... */ }
    .popoverTip(CompareModeTip())
```

**Banners** (control panel sections):

```swift
// Inside the simplification section of ControlPanelView
TipView(SimplificationTip())
```

`TipView` renders as a standard inline banner that the user can dismiss. It automatically hides when the tip is invalidated or max display count is reached.

## 6. Testing

### Unit Tests

- Verify each tip struct has the expected title, message, priority, and max display count.
- Verify each tip's rules reference `ImageLoadedEvent`.

### Manual Testing

- Fresh install (or `Tips.resetDatastore()`): load an image → first tip appears.
- Dismiss tip → no more tips that day.
- Next day (or simulated via `Tips.showAllTipsForTesting()`): next priority tip appears.
- Verify popovers point at correct buttons.
- Verify banners appear in correct control panel sections.
- Verify no tips appear before an image is loaded.

### Debug Support

Add a `#if DEBUG` toggle in `AboutPrivacyView` (or via launch argument) to call `Tips.showAllTipsForTesting()` and `Tips.resetDatastore()` for development iteration.

## 7. Future Considerations

- Additional tips can be added by creating a new struct in `AppTips.swift` and attaching it to the relevant view. No framework changes needed.
- If user research reveals specific discovery gaps, individual tips can add more sophisticated rules (e.g., "user has processed 3+ images but never used depth" via a custom event).
- TipKit supports tip groups (iOS 18) for more structured sequencing if the flat catalog proves insufficient.
