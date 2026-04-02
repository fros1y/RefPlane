import SwiftUI

struct ControlPanelView: View {
    enum Presentation {
        case sheet
        case sidebar
        case bottomPanel
    }

    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: Presentation
    var onClose: (() -> Void)? = nil

    @State private var abstractionStrengthAtDragStart: Double? = nil

    var body: some View {
        Group {
            switch presentation {
            case .sheet:
                inspectorForm
                    .navigationTitle("Adjustments")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if let onClose {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done", action: onClose)
                            }
                        }
                    }
            case .sidebar:
                VStack(spacing: 0) {
                    ActionBarView(showsDismissButton: true, dismissIcon: "sidebar.trailing", onDismiss: closeSidebar)
                    inspectorForm
                }
                .background(Color(.systemGroupedBackground))
            case .bottomPanel:
                // The handle strip in ContentView acts as the header/dismiss affordance.
                inspectorForm
            }
        }
    }

    private var inspectorForm: some View {
        Form {
            Section("Abstraction") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Strength")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(strengthLabel)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.primary)
                    }

                    Slider(
                        value: $state.abstractionStrength,
                        in: 0...1,
                        step: 0.05
                    ) {
                        Text("Strength")
                    } onEditingChanged: { editing in
                        if editing {
                            abstractionStrengthAtDragStart = state.abstractionStrength
                        } else {
                            let changed = abstractionStrengthAtDragStart.map { $0 != state.abstractionStrength } ?? false
                            abstractionStrengthAtDragStart = nil
                            if changed { state.applyAbstraction() }
                        }
                    }
                }

                if state.availableAbstractionMethods.count > 1 {
                    Picker("Style", selection: Binding(
                        get: { state.abstractionMethod },
                        set: { method in
                            state.abstractionMethod = method
                            if state.abstractionIsEnabled {
                                state.applyAbstraction()
                            }
                        }
                    )) {
                        ForEach(state.availableAbstractionMethods) { method in
                            Text(method.label).tag(method)
                        }
                    }
                }

                LabeledSlider(
                    label: "Kuwahara",
                    value: $state.kuwaharaStrength,
                    range: 0...1,
                    step: 0.125,
                    displayFormat: { value in
                        guard value > 0 else { return "Off" }
                        return "R\(Int((value * 8).rounded()))"
                    },
                    onEditingChanged: { editing in
                        if !editing {
                            if state.abstractionIsEnabled {
                                state.applyAbstraction()
                            } else {
                                state.applyKuwahara()
                            }
                        }
                    }
                )
            }

            Section("Depth") {
                DepthSettingsView()
            }

            Section("Mode") {
                ModeBarView()
            }

            if state.activeMode == .value {
                Section("Adjustments") {
                    ValueSettingsView()
                }
            } else if state.activeMode == .color {
                Section("Adjustments") {
                    ColorSettingsView()
                }
            }

            if (state.activeMode == .value || state.activeMode == .color) && !state.paletteColors.isEmpty {
                Section("Palette") {
                    PaletteView()
                }
            }

            Section("Grid") {
                GridSettingsView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private func closeSidebar() {
        if reduceMotion {
            withAnimation(.linear(duration: 0.2)) {
                onClose?()
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                onClose?()
            }
        }
    }

    private var strengthLabel: String {
        state.abstractionIsEnabled ? "\(Int(state.abstractionStrength * 100))%" : "Off"
    }
}
