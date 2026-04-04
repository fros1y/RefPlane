import SwiftUI

struct GridSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            Toggle("Show Grid", isOn: Binding(
                get: { state.gridConfig.enabled },
                set: { state.gridConfig.enabled = $0 }
            ))

            if state.gridConfig.enabled {
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

                Toggle("Diagonals", isOn: Binding(
                    get: { state.gridConfig.showDiagonals },
                    set: { state.gridConfig.showDiagonals = $0 }
                ))

                LabeledPicker(
                    title: "Line Style",
                    selection: Binding(
                        get: { state.gridConfig.lineStyle },
                        set: { state.gridConfig.lineStyle = $0 }
                    ),
                    options: LineStyle.allCases,
                    label: { $0.rawValue }
                )

                if state.gridConfig.lineStyle == .custom {
                    ColorPicker("Color", selection: Binding(
                        get: { state.gridConfig.customColor },
                        set: { state.gridConfig.customColor = $0 }
                    ))
                }

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
