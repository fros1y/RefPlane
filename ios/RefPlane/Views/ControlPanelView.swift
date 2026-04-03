import SwiftUI

enum StudioInspectorSection: String, CaseIterable, Identifiable {
    case study
    case structure
    case depth
    case mixing
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: return "Study"
        case .structure: return "Structure"
        case .depth: return "Depth"
        case .mixing: return "Mixing"
        case .export: return "Export"
        }
    }

    var iconName: String {
        switch self {
        case .study: return "circle.lefthalf.filled"
        case .structure: return "square.grid.3x3"
        case .depth: return "camera.aperture"
        case .mixing: return "paintpalette"
        case .export: return "square.and.arrow.up"
        }
    }

    var summary: String {
        switch self {
        case .study:
            return "Control simplification, painterly filtering, and the active study mode."
        case .structure:
            return "Tune values and drawing guides to simplify composition and proportion."
        case .depth:
            return "Separate foreground from background and add form contours from depth."
        case .mixing:
            return "Build pigment recipes and isolate each mix to evaluate your palette."
        case .export:
            return "Send finished studies to Files, Photos, or another art workflow."
        }
    }
}

struct ControlPanelView: View {
    enum Presentation {
        case sidebar
        case bottomPanel
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var state

    let presentation: Presentation
    @Binding var selectedSection: StudioInspectorSection
    var onClose: (() -> Void)? = nil
    var onOpenPhoto: (() -> Void)? = nil
    var onOpenSamples: (() -> Void)? = nil
    var onExport: (() -> Void)? = nil

    @State private var abstractionStrengthAtDragStart: Double? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerView
            if state.currentDisplayImage != nil {
                inspectorModeStrip
                Divider().opacity(0.18)
            }
            sectionSwitcher
            Divider().opacity(0.18)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    panelBody
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
                Text(selectedSection.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(selectedSection.summary)
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

    private var inspectorModeStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Study Mode")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ModeBarView()
                .accessibilityIdentifier("studio.inspector-mode")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var sectionSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StudioInspectorSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.iconName)
                            .font(.footnote.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(selectedSection == section ? Color.black : Color.primary)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(sectionBackground(isSelected: selectedSection == section))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                    .accessibilityIdentifier("studio.section.\(section.rawValue)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var panelBody: some View {
        switch selectedSection {
        case .study:
            studyPanel
        case .structure:
            structurePanel
        case .depth:
            depthPanel
        case .mixing:
            mixingPanel
        case .export:
            exportPanel
        }
    }

    private var studyPanel: some View {
        VStack(spacing: 16) {
            if state.currentDisplayImage == nil {
                StudioPanelCard(
                    title: "Mode",
                    subtitle: "Choose which study layer is shown on the canvas.",
                    systemImage: "slider.horizontal.below.rectangle",
                    accessibilityID: "studio.card.mode"
                ) {
                    ModeBarView()
                }
            }

            StudioPanelCard(
                title: "Simplify",
                subtitle: "Reduce photo noise and local texture so large shapes read more clearly.",
                systemImage: "wand.and.stars",
                accessibilityID: "studio.card.simplify"
            ) {
                abstractionControls
            }
        }
    }

    private var structurePanel: some View {
        VStack(spacing: 16) {
            if state.activeMode == .value {
                StudioPanelCard(
                    title: "Value Bands",
                    subtitle: "Set the number and spacing of value steps for a stronger notan read.",
                    systemImage: "square.stack.3d.up",
                    accessibilityID: "studio.card.value-bands"
                ) {
                    ValueSettingsView()
                }
            } else {
                StudioPanelCard(
                    title: "Value Bands",
                    subtitle: "Switch to Value mode to edit thresholds and tonal grouping.",
                    systemImage: "square.stack.3d.up",
                    accessibilityID: "studio.card.value-bands"
                ) {
                    ModeBarView()
                }
            }

            StudioPanelCard(
                title: "Drawing Grid",
                subtitle: "Overlay proportional guides, diagonals, and adaptive line colors for transfer work.",
                systemImage: "square.grid.3x3",
                accessibilityID: "studio.card.grid"
            ) {
                GridSettingsView()
            }
        }
    }

    private var depthPanel: some View {
        StudioPanelCard(
            title: "Depth Separation",
            subtitle: "Push backgrounds back, remove distractions, and trace surface contours from estimated depth.",
            systemImage: "camera.aperture",
            accessibilityID: "studio.card.depth"
        ) {
            DepthSettingsView()
        }
    }

    private var mixingPanel: some View {
        VStack(spacing: 16) {
            if state.activeMode == .color {
                StudioPanelCard(
                    title: "Pigment Palette",
                    subtitle: "Choose tubes, limit pigments per mix, and control how broadly regions spread across hue and mass.",
                    systemImage: "paintpalette",
                    accessibilityID: "studio.card.palette"
                ) {
                    ColorSettingsView()
                }

                StudioPanelCard(
                    title: "Mix Recipes",
                    subtitle: state.paletteColors.isEmpty
                        ? "Run a Color study to generate pigment recipes from the current image."
                        : "Tap a mix to isolate that band on canvas and inspect the recipe ratios below.",
                    systemImage: "eyedropper.halffull",
                    accessibilityID: "studio.card.recipes"
                ) {
                    PaletteView()
                }
            } else {
                StudioPanelCard(
                    title: "Mix Recipes",
                    subtitle: "Switch to Color mode to extract palette groups and Golden acrylic recipes.",
                    systemImage: "paintpalette",
                    accessibilityID: "studio.card.recipes"
                ) {
                    ModeBarView()
                }
            }
        }
    }

    private var exportPanel: some View {
        VStack(spacing: 16) {
            StudioPanelCard(
                title: "Output",
                subtitle: "Export the visible study with grid and contour overlays baked in.",
                systemImage: "square.and.arrow.up",
                accessibilityID: "studio.card.export"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: { onExport?() }) {
                        Label("Export Current Study", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.currentDisplayImage == nil)
                    .accessibilityIdentifier("studio.export-current")

                    if state.currentDisplayImage == nil {
                        Text("Load a photo or sample image to enable export.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            StudioPanelCard(
                title: "Source Images",
                subtitle: "Start from your library or a bundled sample set tuned for checking values and color behavior.",
                systemImage: "photo.stack",
                accessibilityID: "studio.card.sources"
            ) {
                VStack(spacing: 12) {
                    Button(action: { onOpenPhoto?() }) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("studio.choose-library")

                    Button(action: { onOpenSamples?() }) {
                        Label("Browse Sample Images", systemImage: "sparkles.rectangle.stack")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("studio.choose-samples")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
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

    private func sectionBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? Color.primary : Color.primary.opacity(0.08))
    }
}

private struct StudioPanelCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accessibilityID: String? = nil
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accessibilityID: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
    @State private var selectedSection: StudioInspectorSection = .study

    var body: some View {
        ControlPanelView(
            presentation: .sidebar,
            selectedSection: $selectedSection
        )
        .environment(state)
        .frame(width: 392, height: 860)
    }
}

#Preview("Inspector") {
    ControlPanelPreviewHarness()
}
