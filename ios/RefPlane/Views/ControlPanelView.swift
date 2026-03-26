import SwiftUI

struct ControlPanelView: View {
    enum Presentation {
        case sheet
        case sidebar
    }

    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: Presentation
    var onClose: (() -> Void)? = nil

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
                    ActionBarView(showsDismissButton: true, onDismiss: closeSidebar)
                    inspectorForm
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private var inspectorForm: some View {
        Form {
            Section("Mode") {
                ModeBarView()
            }

            Section("Simplify") {
                Toggle("Simplify Image", isOn: Binding(
                    get: { state.simplifyEnabled },
                    set: { isEnabled in
                        state.simplifyEnabled = isEnabled
                        if isEnabled {
                            state.applySimplify()
                        } else {
                            state.resetSimplify()
                        }
                    }
                ))

                if state.simplifyEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Strength")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(state.simplifyStrength * 100))%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }

                        Slider(
                            value: $state.simplifyStrength,
                            in: 0...1,
                            step: 0.05
                        ) {
                            Text("Strength")
                        } onEditingChanged: { editing in
                            if !editing {
                                state.applySimplify()
                            }
                        }
                    }

                    if state.availableSimplificationMethods.count > 1 {
                        Picker("Style", selection: Binding(
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
                    }
                }
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
}
