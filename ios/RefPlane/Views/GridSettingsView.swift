import SwiftUI

struct GridSettingsView: View {
    @EnvironmentObject private var state: AppState

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

                LabeledPicker(
                    title: "Cell",
                    selection: Binding(
                        get: { state.gridConfig.cellAspect },
                        set: { state.gridConfig.cellAspect = $0 }
                    ),
                    options: CellAspect.allCases,
                    label: { $0.rawValue }
                )

                Toggle("Diagonals", isOn: Binding(
                    get: { state.gridConfig.showDiagonals },
                    set: { state.gridConfig.showDiagonals = $0 }
                ))

                Toggle("Center Lines", isOn: Binding(
                    get: { state.gridConfig.showCenterLines },
                    set: { state.gridConfig.showCenterLines = $0 }
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
