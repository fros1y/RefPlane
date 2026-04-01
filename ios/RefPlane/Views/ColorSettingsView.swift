import SwiftUI

struct ColorSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var pigmentListExpanded: Bool = false

    var body: some View {
        LabeledSlider(
            label: "Shades",
            value: Binding(
                get: { Double(state.colorConfig.numShades) },
                set: { state.colorConfig.numShades = Int($0.rounded()) }
            ),
            range: 2...24,
            step: 1,
            displayFormat: { "\(Int($0))" },
            onEditingChanged: { editing in
                if !editing {
                    state.triggerProcessing()
                }
            }
        )

        LabeledSlider(
            label: "Palette Spread",
            value: Binding(
                get: { state.colorConfig.paletteSpread },
                set: { state.colorConfig.paletteSpread = $0 }
            ),
            range: 0...1,
            step: 0.01,
            displayFormat: { value in
                if value <= 0.01 { return "Mass" }
                if value >= 0.99 { return "Hue" }
                return String(format: "%.2f", value)
            },
            onEditingChanged: { editing in
                if !editing {
                    state.triggerProcessing()
                }
            }
        )

        if state.activeMode == .color {
            Divider()

            // Preset palette picker
            VStack(alignment: .leading, spacing: 2) {
                Text("Palette")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Picker("Palette", selection: presetBinding) {
                    ForEach(PigmentPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                    Text("Custom").tag(Optional<PigmentPreset>.none as PigmentPreset?)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Pigment checklist
            DisclosureGroup(
                isExpanded: $pigmentListExpanded,
                content: {
                    let pigments = SpectralDataStore.essentialPigments
                    ForEach(pigments) { pigment in
                        PigmentToggleRow(
                            pigment: pigment,
                            isEnabled: state.colorConfig.enabledPigmentIDs.contains(pigment.id),
                            onToggle: { enabled in
                                if enabled {
                                    state.colorConfig.enabledPigmentIDs.insert(pigment.id)
                                } else {
                                    // Prevent disabling all pigments
                                    if state.colorConfig.enabledPigmentIDs.count > 1 {
                                        state.colorConfig.enabledPigmentIDs.remove(pigment.id)
                                    }
                                }
                                pigmentDidChange()
                            }
                        )
                    }
                },
                label: {
                    HStack {
                        Text("Tubes")
                            .font(.subheadline)
                        Spacer()
                        Text("\(state.colorConfig.enabledPigmentIDs.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            )

            LabeledSlider(
                label: "Max Pigments",
                value: Binding(
                    get: { Double(state.colorConfig.maxPigmentsPerMix) },
                    set: { state.colorConfig.maxPigmentsPerMix = Int($0.rounded()) }
                ),
                range: 1...3,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing { state.triggerProcessing() }
                }
            )
        }
    }

    /// Binding that maps the current enabledPigmentIDs to a preset (or nil for custom).
    private var presetBinding: Binding<PigmentPreset?> {
        Binding<PigmentPreset?>(
            get: {
                PigmentPreset.allCases.first { $0.pigmentIDs == state.colorConfig.enabledPigmentIDs }
            },
            set: { newPreset in
                if let preset = newPreset {
                    // Switching to a named preset — save current as custom first
                    // (only if current selection doesn't already match a preset)
                    if PigmentPreset.allCases.first(where: { $0.pigmentIDs == state.colorConfig.enabledPigmentIDs }) == nil {
                        state.colorConfig.saveCustomPigmentIDs()
                    }
                    state.colorConfig.enabledPigmentIDs = preset.pigmentIDs
                    state.colorConfig.saveEnabledPigmentIDs()
                    state.triggerProcessing()
                } else {
                    // "Custom" selected — restore saved custom palette
                    state.colorConfig.enabledPigmentIDs = ColorConfig.loadCustomPigmentIDs()
                    state.colorConfig.saveEnabledPigmentIDs()
                    state.triggerProcessing()
                }
            }
        )
    }

    /// Save current selection and trigger reprocessing.
    private func pigmentDidChange() {
        state.colorConfig.saveEnabledPigmentIDs()
        // Also keep custom palette in sync when in custom mode
        if PigmentPreset.allCases.first(where: { $0.pigmentIDs == state.colorConfig.enabledPigmentIDs }) == nil {
            state.colorConfig.saveCustomPigmentIDs()
        }
        state.triggerProcessing()
    }
}

// MARK: - Pigment toggle row

private struct PigmentToggleRow: View {
    let pigment: PigmentData
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isEnabled)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
                    .imageScale(.medium)

                // Masstone swatch
                Circle()
                    .fill(masstoneColor)
                    .frame(width: 14, height: 14)

                Text(pigment.name)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var masstoneColor: Color {
        let lab = pigment.cielab
        // Approximate CIELab → sRGB for swatch (good enough for display)
        let oklab = KubelkaMunkMixer.pigmentToOklab(
            kOverS: pigment.kOverS,
            database: SpectralDataStore.shared
        )
        let (r, g, b) = oklabToRGB(oklab)
        return Color(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
