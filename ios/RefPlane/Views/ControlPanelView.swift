import SwiftUI

struct ControlPanelView: View {
    enum Presentation {
        case sidebar
        case bottomPanel
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var state

    let presentation: Presentation
    var onClose: (() -> Void)? = nil

    @State private var abstractionStrengthAtDragStart: Double? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerView
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.inspector")
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pipeline")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Edit top to bottom.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .padding(.bottom, 14)
    }

    private var backgroundSection: some View {
        StudioPanelCard(
            title: "Process Background",
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
            title: "Grayscale",
            systemImage: "circle.lefthalf.filled",
            accessibilityID: "studio.card.tonal"
        ) {
            Picker("Rendering", selection: Binding(
                get: { usesTonalRendering },
                set: { setUsesTonalRendering($0) }
            )) {
                Text("Color").tag(false)
                Text("Grayscale").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("studio.rendering-mode")
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
                    Text("Contours need Process Background.")
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
            presentation: .sidebar
        )
        .environment(state)
        .frame(width: 392, height: 860)
    }
}

#Preview("Inspector") {
    ControlPanelPreviewHarness()
}
