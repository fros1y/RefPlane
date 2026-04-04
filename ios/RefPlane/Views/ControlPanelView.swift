import SwiftUI

struct ControlPanelView: View {
    enum Presentation {
        case sidebar
        case bottomPanel
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var state

    let presentation: Presentation
    let onExport: () -> Void
    var onClose: (() -> Void)? = nil

    @State private var abstractionStrengthAtDragStart: Double? = nil
    @State private var savePresetPromptPresented = false
    @State private var renamePresetPromptPresented = false
    @State private var deletePresetPromptPresented = false
    @State private var presetNameInput = ""
    @State private var renamePresetID: UUID? = nil
    @State private var deletePresetID: UUID? = nil
    @State private var presetErrorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider().opacity(0.18)
            presetSelectorBar
            Divider().opacity(0.18)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    backgroundSection
                    simplificationSection
                    tonalSection
                    quantizationSection
                    paletteSection
                    overlaysSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, presentation == .bottomPanel ? 48 : 24)
            }
            .scrollIndicators(.hidden)
            Divider().opacity(0.18)
            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.inspector")
        .alert(
            "Save Current Settings",
            isPresented: $savePresetPromptPresented
        ) {
            TextField("Preset name", text: $presetNameInput)
            Button("Save") {
                saveCurrentPreset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current transformation setup as a reusable preset.")
        }
        .alert(
            "Rename Settings Preset",
            isPresented: $renamePresetPromptPresented
        ) {
            TextField("Preset name", text: $presetNameInput)
            Button("Rename") {
                renameSelectedPreset()
            }
            Button("Cancel", role: .cancel) {
                renamePresetID = nil
            }
        } message: {
            Text("Enter a new name for this preset.")
        }
        .confirmationDialog(
            "Delete this settings preset?",
            isPresented: $deletePresetPromptPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedPreset()
            }
            Button("Cancel", role: .cancel) {
                deletePresetID = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Preset Error", isPresented: Binding(
            get: { presetErrorMessage != nil },
            set: { if !$0 { presetErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                presetErrorMessage = nil
            }
        } message: {
            Text(presetErrorMessage ?? "Unknown preset error.")
        }
    }

    private var presetSelectorBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                if state.shouldShowPreviousSettingsOption {
                    Button("Previous Settings") {
                        state.selectTransformPreset(.previous)
                    }
                    .disabled(!state.hasPreviousTransformSnapshot)
                }

                Button("Default") {
                    state.selectTransformPreset(.appDefault)
                }

                if !state.savedTransformPresets.isEmpty {
                    Divider()

                    ForEach(state.savedTransformPresets) { preset in
                        Menu(preset.name) {
                            Button("Apply") {
                                state.selectTransformPreset(.saved(preset.id))
                            }
                            Button("Rename…") {
                                renamePresetID = preset.id
                                presetNameInput = preset.name
                                renamePresetPromptPresented = true
                            }
                            Button("Delete", role: .destructive) {
                                deletePresetID = preset.id
                                deletePresetPromptPresented = true
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(state.selectedTransformPresetLabel)
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var headerView: some View {
        HStack {
            Spacer()

            if onClose != nil {
                Button(action: closePanel) {
                    Image(systemName: presentation == .sidebar ? "sidebar.trailing" : "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide studio controls")
                .accessibilityIdentifier("studio.inspector-close")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, presentation == .bottomPanel ? 26 : 18)
        .padding(.bottom, 12)
    }

    private var backgroundSection: some View {
        StudioPanelCard(
            title: "Adjust Background",
            systemImage: "camera.aperture",
            accessibilityID: "studio.card.background"
        ) {
            DepthSettingsView()
        }
    }

    private var simplificationSection: some View {
        StudioPanelCard(
            title: "Simplify",
            systemImage: "wand.and.stars",
            accessibilityID: "studio.card.simplify"
        ) {
            abstractionControls
        }
    }

    private var tonalSection: some View {
        StudioPanelCard(
            title: "Grayscale Conversion",
            systemImage: "circle.lefthalf.filled",
            accessibilityID: "studio.card.tonal"
        ) {
            Picker("Method", selection: Binding(
                get: { grayscaleConversionSelection },
                set: selectGrayscaleConversion
            )) {
                ForEach(GrayscaleConversion.allCases) { conversion in
                    Text(conversion.rawValue).tag(conversion)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("studio.grayscale-conversion-picker")
        }
    }

    private var quantizationSection: some View {
        StudioPanelCard(
            title: "Quantize",
            systemImage: "square.stack.3d.up",
            accessibilityID: "studio.card.quantize"
        ) {
            VStack(spacing: 14) {
                Toggle(usesTonalRendering ? "Limit Values" : "Limit Colors", isOn: Binding(
                    get: { usesQuantization },
                    set: { setUsesQuantization($0) }
                ))
                .accessibilityIdentifier("studio.quantize-toggle")

                if usesQuantization {
                    if usesTonalRendering {
                        ValueSettingsView()
                    } else {
                        ColorQuantizationSettingsView()
                    }
                } else {
                    Text(usesTonalRendering ? "Continuous grayscale." : "Full color.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var paletteSection: some View {
        StudioPanelCard(
            title: "Palette Selection",
            systemImage: "paintpalette",
            accessibilityID: "studio.card.palette"
        ) {
            VStack(spacing: 14) {
                Toggle("Use Pigments", isOn: Binding(
                    get: { state.colorConfig.paletteSelectionEnabled },
                    set: setPaletteSelectionEnabled
                ))
                .disabled(!usesQuantization)
                .accessibilityIdentifier("studio.palette-selection-toggle")

                if usesQuantization {
                    if state.colorConfig.paletteSelectionEnabled {
                        PaletteSelectionSettingsView()
                        Divider().opacity(0.18)
                    }
                    PaletteView()
                } else {
                    Text("Turn on Limit Colors or Limit Values.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var overlaysSection: some View {
        StudioPanelCard(
            title: "Overlays",
            systemImage: "square.grid.3x3",
            accessibilityID: "studio.card.overlays"
        ) {
            VStack(spacing: 14) {
                if state.depthMap != nil {
                    ContourSettingsView()
                } else {
                    Text("Contours need Adjust Background.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.18)
                GridSettingsView()
            }
        }
    }

    private var usesTonalRendering: Bool {
        state.activeMode == .tonal || state.activeMode == .value
    }

    private var usesQuantization: Bool {
        state.activeMode == .value || state.activeMode == .color
    }

    private var grayscaleConversionSelection: GrayscaleConversion {
        usesTonalRendering ? state.valueConfig.grayscaleConversion : .none
    }

    private var abstractionControls: some View {
        VStack(spacing: 14) {
            LabeledSlider(
                label: "Strength",
                value: Binding(
                    get: { state.abstractionStrength },
                    set: { state.abstractionStrength = $0 }
                ),
                range: 0...1,
                step: 0.05,
                displayFormat: { value in
                    value > 0 ? "\(Int((value * 100).rounded()))%" : "Off"
                },
                onEditingChanged: handleAbstractionDrag
            )

            if state.availableAbstractionMethods.count > 1 {
                Picker("Style", selection: Binding(
                    get: { state.abstractionMethod },
                    set: selectAbstractionMethod
                )) {
                    ForEach(state.availableAbstractionMethods) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }

            LabeledSlider(
                label: "Kuwahara",
                value: Binding(
                    get: { state.kuwaharaStrength },
                    set: { state.kuwaharaStrength = $0 }
                ),
                range: 0...1,
                step: 0.0625,
                displayFormat: { value in
                    guard value > 0 else { return "Off" }
                    return "R\(Int((value * 16).rounded()))"
                },
                onEditingChanged: handleKuwaharaDrag
            )

        }
    }

    private var footerBar: some View {
        VStack(spacing: 10) {
            Button {
                presetNameInput = state.suggestedTransformPresetName()
                savePresetPromptPresented = true
            } label: {
                Label("Save Current Settings", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("studio.save-settings")

            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.currentDisplayImage == nil)
            .accessibilityIdentifier("studio.export")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, presentation == .bottomPanel ? 34 : 18)
    }

    private func saveCurrentPreset() {
        do {
            try state.saveCurrentTransformPreset(named: presetNameInput)
            presetNameInput = ""
        } catch {
            presetErrorMessage = error.localizedDescription
        }
    }

    private func renameSelectedPreset() {
        guard let renamePresetID else { return }

        do {
            try state.renameTransformPreset(id: renamePresetID, to: presetNameInput)
            self.renamePresetID = nil
            presetNameInput = ""
        } catch {
            presetErrorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedPreset() {
        guard let deletePresetID else { return }
        state.deleteTransformPreset(id: deletePresetID)
        self.deletePresetID = nil
    }

    private func closePanel() {
        guard let onClose else { return }

        if reduceMotion {
            withAnimation(.linear(duration: 0.2), onClose)
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85), onClose)
        }
    }

    private func handleAbstractionDrag(_ editing: Bool) {
        if editing {
            abstractionStrengthAtDragStart = state.abstractionStrength
            return
        }

        let didChange = abstractionStrengthAtDragStart.map { $0 != state.abstractionStrength } ?? false
        abstractionStrengthAtDragStart = nil

        if didChange {
            state.applyAbstraction()
        }
    }

    private func handleKuwaharaDrag(_ editing: Bool) {
        guard !editing else { return }

        if state.abstractionIsEnabled {
            state.applyAbstraction()
        } else {
            state.applyKuwahara()
        }
    }

    private func selectAbstractionMethod(_ method: AbstractionMethod) {
        state.abstractionMethod = method

        if state.abstractionIsEnabled {
            state.applyAbstraction()
        }
    }

    private func setUsesTonalRendering(_ newValue: Bool) {
        state.valueConfig.grayscaleConversion = newValue ? .luminance : .none

        let targetMode: RefPlaneMode
        if newValue {
            targetMode = usesQuantization ? .value : .tonal
        } else {
            targetMode = usesQuantization ? .color : .original
        }
        state.setMode(targetMode)
    }

    private func setUsesQuantization(_ newValue: Bool) {
        if !newValue {
            state.colorConfig.paletteSelectionEnabled = false
        }

        let targetMode: RefPlaneMode
        if newValue {
            targetMode = usesTonalRendering ? .value : .color
        } else {
            targetMode = usesTonalRendering ? .tonal : .original
        }
        state.setMode(targetMode)
    }

    private func setPaletteSelectionEnabled(_ enabled: Bool) {
        guard state.colorConfig.paletteSelectionEnabled != enabled else { return }
        state.colorConfig.paletteSelectionEnabled = enabled
        state.scheduleProcessing()
    }

    private func selectGrayscaleConversion(_ conversion: GrayscaleConversion) {
        guard conversion != grayscaleConversionSelection else { return }
        state.valueConfig.grayscaleConversion = conversion

        let targetMode: RefPlaneMode
        if conversion == .none {
            targetMode = usesQuantization ? .color : .original
        } else {
            targetMode = usesQuantization ? .value : .tonal
        }

        if targetMode == state.activeMode {
            state.scheduleProcessing()
        } else {
            state.setMode(targetMode)
        }
    }
}

private struct StudioPanelCard<Content: View>: View {
    let title: String
    let systemImage: String
    var accessibilityID: String? = nil
    private let content: Content

    init(
        title: String,
        systemImage: String,
        accessibilityID: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityID = accessibilityID
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .studioAccessibilityIdentifier(accessibilityID)
    }

}

private extension View {
    @ViewBuilder
    func studioAccessibilityIdentifier(_ accessibilityID: String?) -> some View {
        if let accessibilityID {
            self
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityID)
        } else {
            self
        }
    }
}

private struct ControlPanelPreviewHarness: View {
    @State private var state = AppState()

    var body: some View {
        ControlPanelView(
            presentation: .sidebar,
            onExport: {}
        )
        .environment(state)
        .frame(width: 392, height: 860)
    }
}

#Preview("Inspector") {
    ControlPanelPreviewHarness()
}
