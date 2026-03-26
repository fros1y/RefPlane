# HIG Compliance & Light Mode — Design

**Date:** 2026-03-26
**Goal:** Make RefPlane look and feel like a native, professional iOS app by adopting Apple Human Interface Guidelines across color, typography, components, materials, spacing, and accessibility. Add full light/dark mode support.

## 1. Color System

Replace all hardcoded colors with iOS semantic colors. Remove `.preferredColorScheme(.dark)` from `RefPlaneApp`.

| Current | Replacement | Purpose |
|---------|-------------|---------|
| `Color(white: 0.10)` | `Color(.systemGroupedBackground)` | Panel background |
| `Color.black` (canvas) | `Color(.systemBackground)` | Canvas background |
| `Color(white: 0.12)` | `Color(.secondarySystemGroupedBackground)` | Subtle surfaces |
| `.foregroundColor(.white)` | `.foregroundStyle(.primary)` | Primary text |
| `.foregroundColor(.white.opacity(0.8))` | `.foregroundStyle(.secondary)` | Secondary text |
| `.foregroundColor(.white.opacity(0.55))` | `.foregroundStyle(.tertiary)` | Tertiary text |
| `.foregroundColor(.white.opacity(0.4))` | `.foregroundStyle(.quaternary)` | Hints |
| `Color.white.opacity(0.07)` | `Color(.tertiarySystemFill)` | Fill backgrounds |
| `Color.white.opacity(0.1)` | `Color(.secondarySystemFill)` | Button backgrounds |
| `Color.white.opacity(0.15)` | `Color(.secondarySystemGroupedBackground)` | Overlay backgrounds |
| Divider `.background(Color.white.opacity(0.12))` | Plain `Divider()` | System dividers |

**Exception:** Image canvas and compare views keep `Color.black` background regardless of appearance — standard for photo/media apps.

## 2. Typography

Replace hardcoded font sizes with Dynamic Type semantic styles.

| Current | Replacement | Where |
|---------|-------------|-------|
| `.system(size: 15, weight: .bold, design: .rounded)` | `.headline` | Header |
| `.system(size: 17, weight: .semibold)` | `.body.weight(.semibold)` | Back button |
| `.system(size: 18)` | `.body` | Action bar icons |
| `.system(size: 14, weight: .semibold)` | `.subheadline.weight(.semibold)` | Mode icons |
| `.system(size: 13, weight: .medium)` | `.subheadline` | "Show Panel" |
| `.system(size: 12, weight: .semibold)` | `.caption.weight(.semibold)` | Chevrons |
| `.system(size: 10)` | `.caption2` | Mode labels, band labels |
| Section headers `.caption` | `.footnote.weight(.semibold)` | PanelSection titles |
| `.system(size: 60)` | Keep fixed | Decorative empty-state icon |

Drop `.design(.rounded)` on the header. Keep `.monospacedDigit()` on numeric readouts.

## 3. Control Panel Structure

Replace custom `PanelSection` + `ScrollView` + `VStack` with native `Form(.grouped)`.

**Before:**
```
VStack → Capsule handle → ActionBar → Divider → ScrollView → VStack → PanelSection(s)
```

**After:**
```
VStack → Collapse handle (44pt target) → ActionBar → Form(.grouped) → Section(s)
```

- Remove `PanelSection` entirely. Native `Section` provides grouped-inset styling, headers, spacing, dividers, and light/dark adaptation for free.
- Per-section collapse is removed. The whole panel already collapses; iOS 17+ `Section(isExpanded:)` available later if needed.
- "RefPlane" + mode label header moves into the action bar area.
- `Form` provides standard 20pt insets, proper row heights, grouped backgrounds, accessible row sizing, and correct separator insets.

## 4. Components

**Mode Bar:** Replace custom `ModeBarView` with native `Picker(.segmented)`:
```swift
Picker("Mode", selection: $state.activeMode) {
    ForEach(RefPlaneMode.allCases) { mode in
        Label(mode.label, systemImage: mode.iconName).tag(mode)
    }
}
.pickerStyle(.segmented)
```

**Action Bar:** Keep HStack layout, use `.buttonStyle(.bordered)` / `.buttonStyle(.borderedProminent)` for active state.

**Notan button:** `.buttonStyle(.bordered)` — standard tinted capsule.

**Collapse handle:** Keep 36x5pt visual capsule, expand `contentShape` to 44pt minimum.

**Back/load button:** `.ultraThinMaterial` background instead of `Color.black.opacity(0.5)`.

**LabeledPicker:** Remove `.colorMultiply(.init(white: 0.8))` hack.

## 5. Materials & Overlays

| Element | Current | Proposed |
|---------|---------|----------|
| Processing overlay | `Color.black.opacity(0.45)` | `.ultraThinMaterial` |
| Error toast bg | `Color(white: 0.15).opacity(0.95)` | `.regularMaterial` |
| Compare labels bg | `Color.black.opacity(0.6)` | `.ultraThinMaterial` + clipShape |
| "Show Panel" capsule | `Color(white: 0.15).opacity(0.95)` | `.regularMaterial` |
| Back button bg | `Color.black.opacity(0.5)` | `.ultraThinMaterial` |

Rule: semi-transparent over media → `.ultraThinMaterial`; floating UI → `.regularMaterial`.

## 6. Spacing & Touch Targets

**8pt grid normalization:**

| Current | Becomes |
|---------|---------|
| 3pt | 4pt (tight groupings only) |
| 6pt, 7pt | 8pt |
| 10pt | 8pt or 12pt |
| 14pt horizontal padding | Removed (Form handles insets) |
| 16pt | 16pt (standard iOS margin) |

**44pt minimum touch targets:**

| Element | Current | Fix |
|---------|---------|-----|
| Collapse handle | ~20pt | `contentShape(Rectangle())` at 44pt |
| Palette band rows | Variable | `.frame(minHeight: 44)` |
| Error toast dismiss | ~22pt | `.frame(minWidth: 44, minHeight: 44)` |

## 7. Accessibility

**Labels:**
- Back button: `.accessibilityLabel("Load new image")`
- Collapse handle: `.accessibilityLabel("Collapse panel")` + hint
- Palette swatches: `.accessibilityLabel("Band N, color M")` + `.isSelected` trait
- Compare slider: `.accessibilityLabel("Comparison divider")` + `.accessibilityValue`
- Processing overlay: `.accessibilityLabel(state.processingLabel)`

**Dynamic Type:** Comes free from semantic text styles + `Form` rows.

**Reduce Motion:** Spring animations fall back to `.linear(duration: 0.2)` or no animation when `AccessibilityReduceMotion` is enabled.
