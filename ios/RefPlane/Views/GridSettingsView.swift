import SwiftUI

struct GridSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Enable toggle
            Toggle("Show Grid", isOn: Binding(
                get: { state.gridConfig.enabled },
                set: { state.gridConfig.enabled = $0 }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .font(.subheadline)

            if state.gridConfig.enabled {
                // Divisions
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

                // Cell aspect
                LabeledPicker(
                    title: "Cell",
                    selection: Binding(
                        get: { state.gridConfig.cellAspect },
                        set: { state.gridConfig.cellAspect = $0 }
                    ),
                    options: CellAspect.allCases,
                    label: { $0.rawValue }
                )

                // Toggles
                Toggle("Diagonals", isOn: Binding(
                    get: { state.gridConfig.showDiagonals },
                    set: { state.gridConfig.showDiagonals = $0 }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .font(.subheadline)

                Toggle("Center Lines", isOn: Binding(
                    get: { state.gridConfig.showCenterLines },
                    set: { state.gridConfig.showCenterLines = $0 }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .font(.subheadline)

                // Line style
                LabeledPicker(
                    title: "Line Style",
                    selection: Binding(
                        get: { state.gridConfig.lineStyle },
                        set: { state.gridConfig.lineStyle = $0 }
                    ),
                    options: LineStyle.allCases,
                    label: { $0.rawValue }
                )

                // Custom color (only when custom style)
                if state.gridConfig.lineStyle == .custom {
                    HStack {
                        Text("Color")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { state.gridConfig.customColor },
                            set: { state.gridConfig.customColor = $0 }
                        ))
                        .labelsHidden()
                    }
                }

                // Opacity
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
}
