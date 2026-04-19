import SwiftUI

struct ColorQuantizationSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            LabeledSlider(
                label: "Count",
                value: Binding(
                    get: { Double(state.transform.colorConfig.numShades) },
                    set: { state.transform.colorConfig.numShades = Int($0.rounded()) }
                ),
                range: 2...24,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing {
                        state.scheduleProcessing()
                    }
                }
            )

            QuantizationBiasSlider(
                value: Binding(
                    get: { state.transform.colorConfig.quantizationBias },
                    set: {
                        state.transform.colorConfig.quantizationBias = QuantizationBias.clamped($0)
                    }
                ),
                onEditingChanged: { editing in
                    if !editing {
                        state.scheduleProcessing()
                    }
                }
            )

            LabeledSlider(
                label: "Group",
                value: Binding(
                    get: { state.transform.colorConfig.paletteSpread },
                    set: { state.transform.colorConfig.paletteSpread = $0 }
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
                        state.scheduleProcessing()
                    }
                }
            )
        }
    }
}

struct PaletteSelectionSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var pigmentListExpanded: Bool = false
    @State private var savePalettePromptPresented = false
    @State private var paletteNameInput = ""
    @State private var paletteErrorMessage: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Palette")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Menu {
                    Section("Built-In") {
                        ForEach(PigmentPreset.allCases) { preset in
                            paletteOptionButton(
                                title: preset.rawValue,
                                pigmentIDs: preset.pigmentIDs
                            )
                        }
                    }

                    if !state.customPaletteStore.examplePalettes.isEmpty {
                        Section("Example Palettes") {
                            ForEach(state.customPaletteStore.examplePalettes) { palette in
                                paletteOptionButton(
                                    title: palette.name,
                                    pigmentIDs: palette.pigmentIDs
                                )
                            }
                        }
                    }

                    if !state.customPaletteStore.savedPalettes.isEmpty {
                        Section("My Palettes") {
                            ForEach(state.customPaletteStore.savedPalettes) { palette in
                                paletteOptionButton(
                                    title: palette.name,
                                    pigmentIDs: Set(palette.pigmentIDs)
                                )
                            }
                        }
                    }

                    Divider()

                    Button("Save Current as…") {
                        paletteNameInput = suggestedPaletteName()
                        savePalettePromptPresented = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(state.customPaletteStore.label(for: state.transform.colorConfig.enabledPigmentIDs))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                }
            }

            DisclosureGroup(
                isExpanded: $pigmentListExpanded,
                content: {
                    let pigments = SpectralDataStore.essentialPigments
                    ForEach(pigments) { pigment in
                        PigmentToggleRow(
                            pigment: pigment,
                            isEnabled: state.transform.colorConfig.enabledPigmentIDs.contains(pigment.id),
                            onToggle: { enabled in
                                if enabled {
                                    state.transform.colorConfig.enabledPigmentIDs.insert(pigment.id)
                                } else {
                                    // Prevent disabling all pigments
                                    if state.transform.colorConfig.enabledPigmentIDs.count > 1 {
                                        state.transform.colorConfig.enabledPigmentIDs.remove(pigment.id)
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
                        Text("\(state.transform.colorConfig.enabledPigmentIDs.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .accessibilityIdentifier("studio.palette-tubes")

            LabeledSlider(
                label: "Mix Size",
                value: Binding(
                    get: { Double(state.transform.colorConfig.maxPigmentsPerMix) },
                    set: { state.transform.colorConfig.maxPigmentsPerMix = Int($0.rounded()) }
                ),
                range: 1...3,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing { state.scheduleProcessing() }
                }
            )
        }
        .alert("Save Palette", isPresented: $savePalettePromptPresented) {
            TextField("Palette name", text: $paletteNameInput)
            Button("Save") {
                saveCurrentPalette()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current tube selection so you can reuse it later.")
        }
        .alert("Palette Error", isPresented: Binding(
            get: { paletteErrorMessage != nil },
            set: { if !$0 { paletteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                paletteErrorMessage = nil
            }
        } message: {
            Text(paletteErrorMessage ?? "Unknown palette error.")
        }
    }

    private func paletteOptionButton(title: String, pigmentIDs: Set<String>) -> some View {
        Button {
            applyPalette(pigmentIDs)
        } label: {
            if pigmentIDs == state.transform.colorConfig.enabledPigmentIDs {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func pigmentDidChange() {
        state.transform.colorConfig.saveEnabledPigmentIDs()
        state.scheduleProcessing()
    }

    private func applyPalette(_ pigmentIDs: Set<String>) {
        state.transform.colorConfig.enabledPigmentIDs = pigmentIDs
        state.transform.colorConfig.saveEnabledPigmentIDs()
        state.scheduleProcessing()
    }

    private func suggestedPaletteName() -> String {
        var index = 1
        while true {
            let candidate = "Palette \(index)"
            let exists = state.customPaletteStore.savedPalettes.contains {
                $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame
            }
            if !exists {
                return candidate
            }
            index += 1
        }
    }

    private func saveCurrentPalette() {
        do {
            _ = try state.customPaletteStore.savePalette(
                named: paletteNameInput,
                pigmentIDs: state.transform.colorConfig.enabledPigmentIDs
            )
            paletteNameInput = ""
        } catch {
            paletteErrorMessage = error.localizedDescription
        }
    }
}

struct ColorSettingsView: View {
    var body: some View {
        ColorQuantizationSettingsView()
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
