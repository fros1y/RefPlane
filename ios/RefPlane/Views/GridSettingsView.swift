import SwiftUI

struct GridSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            Toggle("Show Grid", isOn: Binding(
                get: { state.transform.gridConfig.enabled },
                set: { state.transform.gridConfig.enabled = $0 }
            ))

            if state.transform.gridConfig.enabled {
                LabeledSlider(
                    label: "Divisions",
                    value: Binding(
                        get: { Double(state.transform.gridConfig.divisions) },
                        set: { state.transform.gridConfig.divisions = Int($0.rounded()) }
                    ),
                    range: 2...12,
                    step: 1,
                    displayFormat: { "\(Int($0))" }
                )

                Toggle("Diagonals", isOn: Binding(
                    get: { state.transform.gridConfig.showDiagonals },
                    set: { state.transform.gridConfig.showDiagonals = $0 }
                ))

                LabeledPicker(
                    title: "Line Style",
                    selection: Binding(
                        get: { state.transform.gridConfig.lineStyle },
                        set: { state.transform.gridConfig.lineStyle = $0 }
                    ),
                    options: LineStyle.allCases,
                    label: { $0.rawValue }
                )

                if state.transform.gridConfig.lineStyle == .custom {
                    ColorPicker("Color", selection: Binding(
                        get: { state.transform.gridConfig.customColor },
                        set: { state.transform.gridConfig.customColor = $0 }
                    ))
                }

                LabeledSlider(
                    label: "Opacity",
                    value: Binding(
                        get: { state.transform.gridConfig.opacity },
                        set: { state.transform.gridConfig.opacity = $0 }
                    ),
                    range: 0...1,
                    step: 0.01,
                    displayFormat: { "\(Int($0 * 100))%" }
                )
            }
        }
    }
}
