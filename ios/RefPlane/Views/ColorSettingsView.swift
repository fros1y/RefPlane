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

    private var paletteStore: CustomPaletteStore { .shared }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Palette")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                paletteMenu
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
    }

    private var paletteMenu: some View {
        Menu {
            Section("Presets") {
                ForEach(PigmentPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        applyPigmentSelection(preset.pigmentIDs)
                    }
                }
            }

            if !paletteStore.palettes.isEmpty {
                Section("My Palettes") {
                    ForEach(paletteStore.palettes) { palette in
                        Menu(palette.name) {
                            Button("Apply") {
                                applyPigmentSelection(palette.pigmentIDs)
                            }
                            Button("Delete", role: .destructive) {
                                paletteStore.delete(id: palette.id)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                paletteNameInput = ""
                savePalettePromptPresented = true
            } label: {
                Label("Save Current As…", systemImage: "square.and.arrow.down")
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentPaletteLabel)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("studio.palette-menu")
        .alert("Save Palette", isPresented: $savePalettePromptPresented) {
            TextField("Palette name", text: $paletteNameInput)
            Button("Save") {
                saveCurrentPalette()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the \(state.transform.colorConfig.enabledPigmentIDs.count) selected tubes as a reusable palette.")
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

    private var currentPaletteLabel: String {
        let selection = state.transform.colorConfig.enabledPigmentIDs
        if let preset = PigmentPreset.allCases.first(where: { $0.pigmentIDs == selection }) {
            return preset.rawValue
        }
        if let saved = paletteStore.palette(matching: selection) {
            return saved.name
        }
        return "Custom"
    }

    private func applyPigmentSelection(_ pigmentIDs: Set<String>) {
        let valid = pigmentIDs.intersection(Set(SpectralDataStore.essentialPigments.map(\.id)))
        guard !valid.isEmpty else {
            paletteErrorMessage = "None of this palette's pigments are available."
            return
        }
        state.transform.colorConfig.enabledPigmentIDs = valid
        state.transform.colorConfig.saveEnabledPigmentIDs()
        state.scheduleProcessing()
    }

    private func saveCurrentPalette() {
        do {
            try paletteStore.save(
                name: paletteNameInput,
                pigmentIDs: state.transform.colorConfig.enabledPigmentIDs
            )
            paletteNameInput = ""
        } catch {
            paletteErrorMessage = error.localizedDescription
        }
    }

    /// Save current selection and trigger reprocessing.
    private func pigmentDidChange() {
        state.transform.colorConfig.saveEnabledPigmentIDs()
        // Also keep custom palette in sync when in custom mode
        if PigmentPreset.allCases.first(where: { $0.pigmentIDs == state.transform.colorConfig.enabledPigmentIDs }) == nil {
            state.transform.colorConfig.saveCustomPigmentIDs()
        }
        state.scheduleProcessing()
    }
}

struct ColorSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            ColorQuantizationSettingsView()

            if state.transform.activeMode == .color {
                Divider()
                PaletteSelectionSettingsView()
            }
        }
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
