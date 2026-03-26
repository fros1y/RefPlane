# App Store Follow-Ups Design

**Date:** 2026-03-26
**Status:** Approved

## Scope

Apply the approved App Store compliance follow-ups:

- add a minimal in-app About / Privacy screen
- replace the custom threshold widget with native controls
- remove the unnecessary photo-library usage string
- remove the unsupported crop claim from the README

## Design

### About / Privacy

Add a lightweight sheet from the main toolbar with:

- app name
- author credit for Martin Galese
- a short privacy statement saying the app collects no personal data, uses no analytics, and processes images on-device

This keeps the privacy information easy to reach without adding account, settings, or networking complexity.

### Threshold Controls

Replace the custom multi-handle threshold control with one native `Slider` per threshold value.

Each slider:

- uses normal SwiftUI slider semantics
- keeps its value constrained between neighboring thresholds
- shows a readable threshold label and percentage value

This trades compactness for accessibility and review safety.

### Permissions

Remove `NSPhotoLibraryUsageDescription` from the generated Info.plist settings because image import uses `PHPickerViewController`.

### Metadata

Remove the README crop bullet so shipped documentation matches the current app behavior.
