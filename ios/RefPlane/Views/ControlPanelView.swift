import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Action bar always at top
            ActionBarView()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider().background(Color.white.opacity(0.12))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text("RefPlane")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text(state.activeMode.label)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    // Simplify toggle + strength + method picker
                    PanelSection(title: "Simplify") {
                        Toggle("Enable Simplification", isOn: Binding(
                            get: { state.simplifyEnabled },
                            set: { val in
                                state.simplifyEnabled = val
                                if val { state.applySimplify() } else { state.resetSimplify() }
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .font(.subheadline)

                        if state.simplifyEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Strength")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    Spacer()
                                    Text("\(Int(state.simplifyStrength * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                        .monospacedDigit()
                                }
                                Slider(value: $state.simplifyStrength, in: 0...1, step: 0.05) {
                                    Text("Strength")
                                } onEditingChanged: { editing in
                                    if !editing {
                                        state.applySimplify()
                                    }
                                }
                                .tint(.blue)
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
                                .tint(.blue)
                            }
                        }
                    }

                    // Mode bar
                    PanelSection(title: "Mode") {
                        ModeBarView()
                    }

                    // Adjustments
                    if state.activeMode == .value {
                        PanelSection(title: "Value Settings") {
                            ValueSettingsView()
                        }
                    } else if state.activeMode == .color {
                        PanelSection(title: "Color Settings") {
                            ColorSettingsView()
                        }
                    }

                    // Palette
                    if (state.activeMode == .value || state.activeMode == .color)
                        && !state.paletteColors.isEmpty {
                        PanelSection(title: "Palette") {
                            PaletteView()
                        }
                    }

                    // Grid
                    PanelSection(title: "Grid") {
                        GridSettingsView()
                    }

                    Spacer(minLength: 20)
                }
            }
        }
        .background(Color(white: 0.10))
    }
}

// MARK: - Reusable panel section

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.55))
                        .textCase(.uppercase)
                        .kerning(0.5)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            Divider().background(Color.white.opacity(0.08))
        }
    }
}
