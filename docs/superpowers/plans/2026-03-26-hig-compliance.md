# HIG Compliance & Light Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app look and feel like a native, professional iOS app by adopting Apple HIG across colors, typography, components, materials, spacing, and accessibility — and add full light/dark mode support. Rename the app display name from "RefPlane" to "Underpaint".

**Architecture:** Replace all hardcoded colors with iOS semantic colors, swap custom controls for native equivalents (Form sections, segmented picker, bordered buttons), use system materials for overlays, and enforce 44pt touch targets + accessibility labels. The image canvas stays dark regardless of appearance mode. No new files are created — this is purely updating existing views.

**Tech Stack:** SwiftUI, iOS 16+, no new dependencies

---

## File Map

All changes are modifications to existing files:

| File | Responsibility |
|------|---------------|
| `RefPlaneApp.swift` | Remove forced dark mode |
| `ContentView.swift` | Semantic backgrounds, materials for collapse UI |
| `ControlPanelView.swift` | Form restructure, remove PanelSection |
| `ActionBarView.swift` | Header with "Underpaint" title, bordered buttons |
| `ModeBarView.swift` | Replace with native segmented picker |
| `ThresholdSliderView.swift` | Semantic colors for LabeledSlider, LabeledPicker, handles |
| `GridSettingsView.swift` | Remove manual styling, adapt for Form |
| `ValueSettingsView.swift` | Update Notan button, adapt for Form |
| `ColorSettingsView.swift` | Remove manual styling, adapt for Form |
| `PaletteView.swift` | Semantic colors, 44pt touch targets |
| `ImageCanvasView.swift` | Dark environment, materials for overlays |
| `CompareView.swift` | Dark environment, materials for labels |
| `ErrorToastView.swift` | Material background, semantic colors |

---

### Task 1: Foundation — Remove forced dark mode, pin canvas to dark

**Files:**
- Modify: `ios/RefPlane/RefPlaneApp.swift`
- Modify: `ios/RefPlane/Views/ImageCanvasView.swift`
- Modify: `ios/RefPlane/Views/CompareView.swift`

- [ ] **Step 1: Remove forced dark mode from app entry point**

In `RefPlaneApp.swift`, remove `.preferredColorScheme(.dark)`:

```swift
@main
struct RefPlaneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 2: Pin ImageCanvasView to dark color scheme**

The canvas displays photos — it must stay dark regardless of system appearance. In `ImageCanvasView.swift`, add `.environment(\.colorScheme, .dark)` to the outermost `GeometryReader`:

At the end of the `GeometryReader` (after the closing brace of the ZStack), add the modifier:

```swift
        } // end GeometryReader
        .environment(\.colorScheme, .dark)
    }
}
```

- [ ] **Step 3: Pin CompareView and CompareSliderView to dark**

In `CompareView.swift`, add `.environment(\.colorScheme, .dark)` to both views.

For `CompareView`, add it after `.ignoresSafeArea()`:

```swift
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
```

For `CompareSliderView`, add it after the `GeometryReader`'s closing brace:

```swift
        } // end GeometryReader
        .environment(\.colorScheme, .dark)
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds. The app will look broken (hardcoded white text on light backgrounds in the control panel) — this is expected and will be fixed in subsequent tasks.

- [ ] **Step 5: Commit**

```bash
git add ios/RefPlane/RefPlaneApp.swift ios/RefPlane/Views/ImageCanvasView.swift ios/RefPlane/Views/CompareView.swift
git commit -m "refactor: Remove forced dark mode, pin canvas views to dark scheme"
```

---

### Task 2: Helper Components — Semantic colors

**Files:**
- Modify: `ios/RefPlane/Views/ThresholdSliderView.swift`

This file contains `ThresholdSliderView`, `LabeledSlider`, and `LabeledPicker` — reusable components used throughout the settings views. Update them first so downstream views inherit correct styling.

- [ ] **Step 1: Update LabeledSlider**

Replace the `LabeledSlider` body with semantic colors:

```swift
struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayFormat: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displayFormat(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
```

Changes: `.foregroundColor(.white.opacity(0.8))` → `.foregroundStyle(.secondary)`, `.foregroundColor(.white.opacity(0.6))` → `.foregroundStyle(.tertiary)`, removed `.tint(.blue)` (inherits accent color).

- [ ] **Step 2: Update LabeledPicker — remove colorMultiply hack**

Replace the `LabeledPicker` body:

```swift
struct LabeledPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(label(opt)).tag(opt)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
```

Changes: `.foregroundColor(.white.opacity(0.8))` → `.foregroundStyle(.secondary)`, removed `.colorMultiply(.init(white: 0.8))`.

- [ ] **Step 3: Update ThresholdSliderView handles**

In the `ThresholdSliderView`, the track colors come from the `colorForLevel` closure (called by the parent — grayscale bands), so those stay. Update the handle styling:

Replace the handle `RoundedRectangle`:

```swift
RoundedRectangle(cornerRadius: 3)
    .fill(Color(.systemBackground))
    .frame(width: handleW, height: trackH + 8)
    .shadow(color: Color(.separator), radius: 2)
    .offset(x: x)
```

Change: `.fill(Color.white)` → `.fill(Color(.systemBackground))`, `.shadow(radius: 2)` → `.shadow(color: Color(.separator), radius: 2)`. Handles will be white on dark, dark on light.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ios/RefPlane/Views/ThresholdSliderView.swift
git commit -m "refactor: Update helper components with semantic colors"
```

---

### Task 3: Control Panel — Form restructure

**Files:**
- Modify: `ios/RefPlane/Views/ControlPanelView.swift`

This is the largest single change. Replace the custom `ScrollView` + `VStack` + `PanelSection` with a native `Form`. Remove the `PanelSection` struct entirely.

- [ ] **Step 1: Rewrite ControlPanelView body**

Replace the entire file with:

```swift
import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Collapse handle — 44pt touch target
            Button {
                withAnimation(reduceMotion
                    ? .linear(duration: 0.2)
                    : .spring(response: 0.3, dampingFraction: 0.8)
                ) {
                    state.panelCollapsed = true
                }
            } label: {
                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse panel")

            // Action bar (pinned above form)
            ActionBarView()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider()

            // Settings
            Form {
                Section("Simplify") {
                    Toggle("Enable Simplification", isOn: Binding(
                        get: { state.simplifyEnabled },
                        set: { val in
                            state.simplifyEnabled = val
                            if val { state.applySimplify() } else { state.resetSimplify() }
                        }
                    ))

                    if state.simplifyEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Strength")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(state.simplifyStrength * 100))%")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            Slider(value: $state.simplifyStrength, in: 0...1, step: 0.05) {
                                Text("Strength")
                            } onEditingChanged: { editing in
                                if !editing {
                                    state.applySimplify()
                                }
                            }
                        }

                        if state.availableSimplificationMethods.count > 1 {
                            Picker("Method", selection: Binding(
                                get: { state.simplificationMethod },
                                set: { method in
                                    state.simplificationMethod = method
                                    if state.simplifyEnabled {
                                        state.applySimplify()
                                    }
                                }
                            )) {
                                ForEach(state.availableSimplificationMethods) { method in
                                    Text(method.label).tag(method)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                Section("Mode") {
                    ModeBarView()
                }

                if state.activeMode == .value {
                    Section("Value Settings") {
                        ValueSettingsView()
                    }
                } else if state.activeMode == .color {
                    Section("Color Settings") {
                        ColorSettingsView()
                    }
                }

                if (state.activeMode == .value || state.activeMode == .color)
                    && !state.paletteColors.isEmpty {
                    Section("Palette") {
                        PaletteView()
                    }
                }

                Section("Grid") {
                    GridSettingsView()
                }
            }
            .formStyle(.grouped)
        }
    }
}
```

This removes `PanelSection` entirely. The `Form` provides grouped-inset styling, section headers, row spacing, dividers, and proper light/dark backgrounds automatically.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds. The control panel now renders with native grouped Form styling.

- [ ] **Step 3: Commit**

```bash
git add ios/RefPlane/Views/ControlPanelView.swift
git commit -m "refactor: Replace custom panel sections with native Form"
```

---

### Task 4: Action Bar — Header + bordered buttons

**Files:**
- Modify: `ios/RefPlane/Views/ActionBarView.swift`

Replace custom `ActionButton` with "Underpaint" title + native bordered buttons.

- [ ] **Step 1: Rewrite ActionBarView**

Replace the entire file with:

```swift
import SwiftUI

struct ActionBarView: View {
    @EnvironmentObject private var state: AppState
    @State private var exportItem: ExportItem?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Underpaint")
                    .font(.headline)
                Text(state.activeMode.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Spacer()
            HStack(spacing: 8) {
                Toggle(isOn: $state.compareMode) {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .disabled(state.displayBaseImage == nil)

                Button {
                    if let img = state.exportCurrentImage() {
                        exportItem = ExportItem(image: img)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.currentDisplayImage == nil)
            }
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.image])
        }
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

Changes: Custom `ActionButton` removed. Compare uses `Toggle(.button)` for automatic active/inactive styling. Export uses `.buttonStyle(.bordered)`. "Underpaint" title + mode label replaces the old header from ControlPanelView.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ios/RefPlane/Views/ActionBarView.swift
git commit -m "refactor: Restyle action bar with Underpaint title and native buttons"
```

---

### Task 5: Mode Bar — Native segmented picker

**Files:**
- Modify: `ios/RefPlane/Views/ModeBarView.swift`

Replace the entire custom mode bar with a native `Picker(.segmented)`.

- [ ] **Step 1: Rewrite ModeBarView**

Replace the entire file with:

```swift
import SwiftUI

struct ModeBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { state.activeMode },
            set: { state.setMode($0) }
        )) {
            ForEach(RefPlaneMode.allCases) { mode in
                Label(mode.label, systemImage: mode.iconName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}
```

Changes: Removed `ModeButton`, `ModeButtonStyle`, custom backgrounds, manual animations. The native segmented control handles active state highlighting, light/dark adaptation, and accessibility automatically. Uses `Binding(get:set:)` to call `state.setMode(_:)` on change (preserving the processing trigger).

Note: `Label` in a segmented picker may show only the text or only the icon depending on available space. If both icon+text are desired, this can be adjusted after visual testing — but the standard iOS behavior is to show text in segmented controls.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ios/RefPlane/Views/ModeBarView.swift
git commit -m "refactor: Replace custom mode bar with native segmented picker"
```

---

### Task 6: Settings Views — Adapt for Form context

**Files:**
- Modify: `ios/RefPlane/Views/GridSettingsView.swift`
- Modify: `ios/RefPlane/Views/ValueSettingsView.swift`
- Modify: `ios/RefPlane/Views/ColorSettingsView.swift`

These views are now inside `Form > Section`. Remove the outer `VStack` wrappers so each control becomes a proper Form row. Remove manual foreground colors and toggle tints — Form provides these automatically.

- [ ] **Step 1: Update GridSettingsView**

Replace the entire file with:

```swift
import SwiftUI

struct GridSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Toggle("Show Grid", isOn: Binding(
            get: { state.gridConfig.enabled },
            set: { state.gridConfig.enabled = $0 }
        ))

        if state.gridConfig.enabled {
            LabeledSlider(
                label: "Divisions",
                value: Binding(
                    get: { Double(state.gridConfig.divisions) },
                    set: { state.gridConfig.divisions = Int($0.rounded()) }
                ),
                range: 2...12,
                step: 1,
                displayFormat: { "\(Int($0))" }
            )

            LabeledPicker(
                title: "Cell",
                selection: Binding(
                    get: { state.gridConfig.cellAspect },
                    set: { state.gridConfig.cellAspect = $0 }
                ),
                options: CellAspect.allCases,
                label: { $0.rawValue }
            )

            Toggle("Diagonals", isOn: Binding(
                get: { state.gridConfig.showDiagonals },
                set: { state.gridConfig.showDiagonals = $0 }
            ))

            Toggle("Center Lines", isOn: Binding(
                get: { state.gridConfig.showCenterLines },
                set: { state.gridConfig.showCenterLines = $0 }
            ))

            LabeledPicker(
                title: "Line Style",
                selection: Binding(
                    get: { state.gridConfig.lineStyle },
                    set: { state.gridConfig.lineStyle = $0 }
                ),
                options: LineStyle.allCases,
                label: { $0.rawValue }
            )

            if state.gridConfig.lineStyle == .custom {
                ColorPicker("Color", selection: Binding(
                    get: { state.gridConfig.customColor },
                    set: { state.gridConfig.customColor = $0 }
                ))
            }

            LabeledSlider(
                label: "Opacity",
                value: Binding(
                    get: { state.gridConfig.opacity },
                    set: { state.gridConfig.opacity = $0 }
                ),
                range: 0...1,
                step: 0.01,
                displayFormat: { "\(Int($0 * 100))%" }
            )
        }
    }
}
```

Changes: Removed outer `VStack(alignment: .leading, spacing: 10)`. Each control is now a top-level child — inside the parent `Section`, each becomes a proper Form row. Removed `.toggleStyle(SwitchToggleStyle(tint: .blue))` (Form default is switch with accent tint). Removed `.font(.subheadline)` from toggles (Form provides default sizing). Simplified the ColorPicker — removed manual HStack + labelsHidden; the `ColorPicker("Color", ...)` label renders natively in Form.

- [ ] **Step 2: Update ValueSettingsView**

Replace the entire file with:

```swift
import SwiftUI

struct ValueSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button("Notan (2 levels)", action: applyNotan)
            .buttonStyle(.bordered)

        LabeledSlider(
            label: "Levels",
            value: Binding(
                get: { Double(state.valueConfig.levels) },
                set: { newVal in
                    let lvl = Int(newVal.rounded())
                    state.valueConfig.levels = lvl
                    state.valueConfig.thresholds = defaultThresholds(for: lvl)
                    state.triggerProcessing()
                }
            ),
            range: 2...8,
            step: 1,
            displayFormat: { "\(Int($0))" }
        )

        VStack(alignment: .leading, spacing: 4) {
            Text("Thresholds")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ThresholdSliderView(
                thresholds: Binding(
                    get: { state.valueConfig.thresholds },
                    set: { state.valueConfig.thresholds = $0; state.triggerProcessing() }
                ),
                levels: state.valueConfig.levels,
                colorForLevel: { level, total in
                    let t = total > 1 ? Float(level) / Float(total - 1) : 0.5
                    return Color(white: Double(t))
                }
            )
        }

        LabeledPicker(
            title: "Min Region",
            selection: Binding(
                get: { state.valueConfig.minRegionSize },
                set: { state.valueConfig.minRegionSize = $0; state.triggerProcessing() }
            ),
            options: MinRegionSize.allCases,
            label: { $0.rawValue }
        )
    }

    private func applyNotan() {
        state.valueConfig.levels = 2
        state.valueConfig.thresholds = [0.5]
        state.triggerProcessing()
    }
}
```

Changes: Removed outer VStack. Notan button uses `.buttonStyle(.bordered)` — renders as a tinted Form row button. Removed manual foreground/background styling. Threshold label uses `.foregroundStyle(.secondary)` and `.font(.footnote)`.

- [ ] **Step 3: Update ColorSettingsView**

Replace the entire file with:

```swift
import SwiftUI

struct ColorSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        LabeledSlider(
            label: "Value Bands",
            value: Binding(
                get: { Double(state.colorConfig.bands) },
                set: { newVal in
                    let bands = Int(newVal.rounded())
                    state.colorConfig.bands = bands
                    state.colorConfig.thresholds = defaultThresholds(for: bands)
                    state.triggerProcessing()
                }
            ),
            range: 2...6,
            step: 1,
            displayFormat: { "\(Int($0))" }
        )

        LabeledSlider(
            label: "Colors / Band",
            value: Binding(
                get: { Double(state.colorConfig.colorsPerBand) },
                set: { newVal in
                    state.colorConfig.colorsPerBand = Int(newVal.rounded())
                    state.triggerProcessing()
                }
            ),
            range: 1...4,
            step: 1,
            displayFormat: { "\(Int($0))" }
        )

        LabeledSlider(
            label: "Warm/Cool",
            value: Binding(
                get: { state.colorConfig.warmCoolEmphasis },
                set: { state.colorConfig.warmCoolEmphasis = $0; state.triggerProcessing() }
            ),
            range: -1...1,
            step: 0.01,
            displayFormat: { String(format: "%.2f", $0) }
        )

        VStack(alignment: .leading, spacing: 4) {
            Text("Band Thresholds")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ThresholdSliderView(
                thresholds: Binding(
                    get: { state.colorConfig.thresholds },
                    set: { state.colorConfig.thresholds = $0; state.triggerProcessing() }
                ),
                levels: state.colorConfig.bands,
                colorForLevel: { level, total in
                    let t = total > 1 ? Double(level) / Double(total - 1) : 0.5
                    return Color(white: t)
                }
            )
        }

        LabeledPicker(
            title: "Min Region",
            selection: Binding(
                get: { state.colorConfig.minRegionSize },
                set: { state.colorConfig.minRegionSize = $0; state.triggerProcessing() }
            ),
            options: MinRegionSize.allCases,
            label: { $0.rawValue }
        )
    }
}
```

Changes: Removed outer VStack. Removed manual `.foregroundColor` and `.font(.caption)`. Threshold label uses `.foregroundStyle(.secondary)` and `.font(.footnote)`.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds. Settings sections render with native Form row styling.

- [ ] **Step 5: Commit**

```bash
git add ios/RefPlane/Views/GridSettingsView.swift ios/RefPlane/Views/ValueSettingsView.swift ios/RefPlane/Views/ColorSettingsView.swift
git commit -m "refactor: Adapt settings views for native Form context"
```

---

### Task 7: Palette View — Semantic colors + touch targets

**Files:**
- Modify: `ios/RefPlane/Views/PaletteView.swift`

- [ ] **Step 1: Update PaletteView**

Replace the entire file with:

```swift
import SwiftUI

struct PaletteView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let maxBand = (state.paletteBands.max() ?? -1)
        if maxBand >= 0 {
            ForEach(0...maxBand, id: \.self) { band in
                let indices = state.paletteBands.enumerated()
                    .filter { $0.element == band }
                    .map { $0.offset }
                if !indices.isEmpty {
                    HStack(spacing: 4) {
                        Text("Band \(band + 1)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, alignment: .leading)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(indices, id: \.self) { idx in
                                    let color = state.paletteColors[idx]
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(color)
                                        .frame(width: 32, height: 24)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(
                                                    state.isolatedBand == band
                                                        ? Color.accentColor : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                }
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if state.isolatedBand == band {
                            state.isolatedBand = nil
                        } else {
                            state.isolatedBand = band
                        }
                    }
                    .accessibilityLabel("Band \(band + 1), \(indices.count) colors")
                    .accessibilityAddTraits(state.isolatedBand == band ? .isSelected : [])
                }
            }
        }
    }
}
```

Changes: Removed outer VStack (children become individual Form rows via ForEach). `.foregroundColor(.white.opacity(0.4))` → `.foregroundStyle(.tertiary)`. Selection stroke uses `.accentColor` instead of `.white`. Added `.frame(minHeight: 44)` for touch targets. Added accessibility label and selected trait. Band label width bumped from 42 to 44.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ios/RefPlane/Views/PaletteView.swift
git commit -m "refactor: Update palette with semantic colors and touch targets"
```

---

### Task 8: Image Canvas — Materials for overlays

**Files:**
- Modify: `ios/RefPlane/Views/ImageCanvasView.swift`

- [ ] **Step 1: Update back button overlay**

Replace the back button (inside `if state.originalImage != nil`) with material background:

```swift
if state.originalImage != nil {
    Button(action: { showImagePicker = true }) {
        Image(systemName: "arrow.backward")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
    .padding(.leading, 16)
    .padding(.top, 16)
    .accessibilityLabel("Load new image")
}
```

Changes: `.font(.system(size: 17, weight: .semibold))` → `.font(.body.weight(.semibold))`. `Color.black.opacity(0.5)` → `.ultraThinMaterial`. `.foregroundColor(.white.opacity(0.85))` → `.foregroundStyle(.primary)`. Added `.accessibilityLabel`. Padding normalized to 16/12.

- [ ] **Step 2: Update processing overlay**

Replace the processing overlay (inside `if state.isProcessing`) with material:

```swift
if state.isProcessing {
    ZStack {
        Color.black.opacity(0.2)
            .background(.ultraThinMaterial)
        VStack(spacing: 12) {
            if state.processingIsIndeterminate {
                ProgressView()
                    .scaleEffect(1.2)
            } else {
                ProgressView(value: state.processingProgress)
                    .frame(width: 160)
            }
            Text(state.processingLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .ignoresSafeArea()
    .accessibilityLabel(state.processingLabel)
}
```

Changes: `Color.black.opacity(0.45)` → `Color.black.opacity(0.2)` + `.ultraThinMaterial`. Removed `.tint(.white)` (inherits from dark environment). `.foregroundColor(.white.opacity(0.8))` → `.foregroundStyle(.secondary)`. Spacing 10 → 12. Added accessibility label.

- [ ] **Step 3: Update empty state**

Replace the empty state button:

```swift
Button(action: { showImagePicker = true }) {
    VStack(spacing: 16) {
        Image(systemName: "photo.on.rectangle")
            .font(.system(size: 60))
            .foregroundStyle(.tertiary)
        Text("Tap to open an image")
            .font(.headline)
            .foregroundStyle(.quaternary)
    }
}
.buttonStyle(.plain)
```

Changes: `.foregroundColor(.white.opacity(0.3))` → `.foregroundStyle(.tertiary)`. `.foregroundColor(.white.opacity(0.4))` → `.foregroundStyle(.quaternary)`.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ios/RefPlane/Views/ImageCanvasView.swift
git commit -m "refactor: Use materials and semantic styles for canvas overlays"
```

---

### Task 9: Content View — Materials + semantic backgrounds

**Files:**
- Modify: `ios/RefPlane/Views/ContentView.swift`

- [ ] **Step 1: Update landscape collapse strip**

Replace the landscape collapse button (inside `if state.panelCollapsed` in the `geo.size.width > geo.size.height` branch):

```swift
if state.panelCollapsed {
    Button {
        withAnimation(reduceMotion
            ? .linear(duration: 0.2)
            : .spring(response: 0.3, dampingFraction: 0.8)
        ) {
            state.panelCollapsed = false
        }
    } label: {
        Image(systemName: "chevron.left")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
    }
    .buttonStyle(.plain)
    .transition(.move(edge: .trailing))
    .accessibilityLabel("Show panel")
}
```

Changes: `.font(.system(size: 14, weight: .semibold))` → `.font(.caption.weight(.semibold))`. `.foregroundColor(.white.opacity(0.7))` → `.foregroundStyle(.secondary)`. `Color(white: 0.12)` → `Color(.secondarySystemGroupedBackground)`.

- [ ] **Step 2: Update landscape divider and panel**

Replace the divider and panel in the else branch:

```swift
} else {
    Divider()
    ControlPanelView()
        .frame(width: 284)
        .transition(.move(edge: .trailing))
}
```

Change: `Divider().background(Color.white.opacity(0.15))` → plain `Divider()`.

- [ ] **Step 3: Update portrait collapse capsule**

Replace the portrait collapse button (inside `if state.panelCollapsed` in the else/portrait branch):

```swift
if state.panelCollapsed {
    Button {
        withAnimation(reduceMotion
            ? .linear(duration: 0.2)
            : .spring(response: 0.3, dampingFraction: 0.8)
        ) {
            state.panelCollapsed = false
        }
    } label: {
        HStack(spacing: 8) {
            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
            Text("Show Panel")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: Color(.separator).opacity(0.4), radius: 8, y: 2)
    }
    .buttonStyle(.plain)
    .padding(.bottom, 16)
    .transition(.move(edge: .bottom).combined(with: .opacity))
    .accessibilityLabel("Show panel")
}
```

Changes: `.font(.system(size: 12/13))` → `.font(.caption/.subheadline)`. `.foregroundColor(.white)` → `.foregroundStyle(.primary)`. `Color(white: 0.15).opacity(0.95)` → `.regularMaterial`. `.shadow(color: .black.opacity(0.4))` → `.shadow(color: Color(.separator).opacity(0.4))`. Spacing 6 → 8.

- [ ] **Step 4: Update root background and add reduceMotion**

Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to ContentView.

Update the root background and existing collapse animations:

```swift
.background(Color(.systemBackground))
```

Change: `Color.black` → `Color(.systemBackground)`.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add ios/RefPlane/Views/ContentView.swift
git commit -m "refactor: Use materials and semantic colors in content layout"
```

---

### Task 10: Compare Views + Error Toast — Materials

**Files:**
- Modify: `ios/RefPlane/Views/CompareView.swift`
- Modify: `ios/RefPlane/Views/ErrorToastView.swift`

- [ ] **Step 1: Update CompareView labels and close button**

In `CompareView`, replace the "Before"/"After" label backgrounds and close button.

Replace the labels VStack:

```swift
VStack {
    HStack {
        Label("Before", systemImage: "photo")
            .font(.caption)
            .padding(5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.leading, 12)
        Spacer()
        Label("After", systemImage: "wand.and.stars")
            .font(.caption)
            .padding(5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.trailing, 12)
    }
    .foregroundStyle(.primary)
    .padding(.top, 48)
    Spacer()
}
```

Changes: `Color.black.opacity(0.6)` → `.ultraThinMaterial`. `.cornerRadius(6)` → `.clipShape(RoundedRectangle(cornerRadius: 6))`. `.foregroundColor(.white)` → `.foregroundStyle(.primary)`. Padding 10 → 12.

Replace the close button:

```swift
.overlay(alignment: .topTrailing) {
    Button(action: { dismiss() }) {
        Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .padding(16)
    }
}
```

Changes: `.foregroundColor(.white.opacity(0.8))` → `.symbolRenderingMode(.hierarchical)` + `.foregroundStyle(.primary)`.

- [ ] **Step 2: Update CompareSliderView labels**

In `CompareSliderView`, apply the same label changes. Replace the labels VStack:

```swift
VStack {
    HStack {
        Label("Before", systemImage: "photo")
            .font(.caption)
            .padding(5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.leading, 12)
        Spacer()
        Label("After", systemImage: "wand.and.stars")
            .font(.caption)
            .padding(5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.trailing, 12)
    }
    .foregroundStyle(.primary)
    .padding(.top, 8)
    Spacer()
}
```

- [ ] **Step 3: Add accessibility to compare dividers**

In both `CompareView` and `CompareSliderView`, add accessibility to the divider handle ZStack:

After the `.gesture(DragGesture()...)` modifier on the divider ZStack, add:

```swift
.accessibilityLabel("Comparison divider")
.accessibilityValue("\(Int(splitFraction * 100)) percent from left")
```

- [ ] **Step 4: Update ErrorToastView**

Replace the entire file:

```swift
import SwiftUI

struct ErrorToastView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(.separator).opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: message)
    }
}
```

Changes: `Color(white: 0.15).opacity(0.95)` → `.regularMaterial`. `.foregroundColor(.white)` → `.foregroundStyle(.primary)`. `.foregroundColor(.white.opacity(0.7))` → `.foregroundStyle(.secondary)`. Dismiss button has `.frame(minWidth: 44, minHeight: 44)` for touch target. `.shadow(color: .black.opacity(0.4))` → `.shadow(color: Color(.separator).opacity(0.3))`. `.cornerRadius(12)` → `.clipShape(RoundedRectangle(cornerRadius: 12))`. Spacing 10 → 12. Adjusted padding to accommodate 44pt dismiss button.

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add ios/RefPlane/Views/CompareView.swift ios/RefPlane/Views/ErrorToastView.swift
git commit -m "refactor: Use materials for compare labels and error toast"
```

---

### Task 11: Rename display name to Underpaint

**Files:**
- Modify: `ios/RefPlane.xcodeproj/project.pbxproj` (bundle display name)
- Modify: `ios/RefPlane/Info.plist` (if it exists and has display name)

- [ ] **Step 1: Check for existing Info.plist**

Run: `find ios/ -name "Info.plist" -type f`

If an Info.plist exists, check if it has `CFBundleDisplayName` or `CFBundleName`. If the project uses the default Xcode-generated Info.plist (set in build settings), add `INFOPLIST_KEY_CFBundleDisplayName = Underpaint` to the build settings.

- [ ] **Step 2: Set the bundle display name**

In the Xcode project build settings, set `INFOPLIST_KEY_CFBundleDisplayName` to `Underpaint`. This can be done by adding the key to the project.pbxproj build settings sections, or by adding a custom Info.plist key.

The simplest approach: add an `InfoPlist.strings` is unnecessary. Instead, directly set the build setting. Open `project.pbxproj` and in both Debug and Release `buildSettings` blocks for the RefPlane target, add:

```
INFOPLIST_KEY_CFBundleDisplayName = Underpaint;
```

This controls the name shown under the app icon on the home screen and in the App Store.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -project ios/RefPlane.xcodeproj -scheme RefPlane -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`

Expected: Build succeeds. The app icon label on the home screen reads "Underpaint".

- [ ] **Step 4: Commit**

```bash
git add ios/RefPlane.xcodeproj/project.pbxproj
git commit -m "chore: Rename app display name to Underpaint"
```

---

### Task 12: Visual verification + cleanup

This is the final pass to catch anything missed and verify both appearances.

- [ ] **Step 1: Build and run in light mode**

Run the app in the iOS Simulator. Set the simulator appearance to Light (Features → Appearance → Light). Verify:
- Control panel has white/light gray grouped Form background
- Section headers are standard footnote style
- Toggles, sliders, pickers use accent blue tint
- Canvas area stays dark
- Back button and processing overlay use frosted materials
- Error toast uses frosted material
- "Show Panel" capsule uses frosted material
- All text is legible
- "Underpaint" header shows in the action bar

- [ ] **Step 2: Build and run in dark mode**

Set the simulator to Dark (Features → Appearance → Dark). Verify:
- Control panel has dark grouped Form background
- Canvas area stays dark (no change)
- Materials adapt to dark appearance
- All elements are legible and consistent

- [ ] **Step 3: Check for any remaining hardcoded colors**

Run: `grep -rn "Color(white:" ios/RefPlane/Views/ && grep -rn "\.foregroundColor(.white" ios/RefPlane/Views/`

The only results should be from:
- `Color(white: t)` in ThresholdSliderView color callbacks (these are the grayscale band colors — intentionally fixed)
- Compare view divider handle: `Color.white` for the line and circle (intentionally white on dark canvas)

Any other hits are bugs — fix them.

- [ ] **Step 4: Check for remaining .tint(.blue) calls**

Run: `grep -rn "\.tint(.blue)" ios/RefPlane/Views/`

Expected: No results. All explicit `.tint(.blue)` should have been removed (Form inherits accent color automatically).

- [ ] **Step 5: Commit any fixes**

If any fixes were needed from steps 3-4:

```bash
git add -A ios/RefPlane/Views/
git commit -m "fix: Clean up remaining hardcoded colors"
```
