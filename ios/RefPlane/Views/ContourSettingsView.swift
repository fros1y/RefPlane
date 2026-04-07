import SwiftUI

struct ContourSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            Toggle("Surface Contours", isOn: Binding(
                get: { state.transform.contourConfig.enabled },
                set: { newValue in
                    state.transform.contourConfig.enabled = newValue
                    if newValue {
                        state.recomputeContours()
                    } else {
                        state.depth.contourSegments = []
                    }
                }
            ))

            if state.transform.contourConfig.enabled {
                LabeledSlider(
                    label: "Levels",
                    value: Binding(
                        get: { Double(state.transform.contourConfig.levels) },
                        set: { state.transform.contourConfig.levels = Int($0.rounded()) }
                    ),
                    range: 2...64,
                    step: 1,
                    displayFormat: { "\(Int($0))" },
                    onEditingChanged: { editing in
                        if !editing {
                            state.recomputeContours()
                        }
                    }
                )

                LabeledPicker(
                    title: "Line Style",
                    selection: Binding(
                        get: { state.transform.contourConfig.lineStyle },
                        set: { state.transform.contourConfig.lineStyle = $0 }
                    ),
                    options: LineStyle.allCases,
                    label: { $0.rawValue }
                )

                if state.transform.contourConfig.lineStyle == .custom {
                    ColorPicker("Color", selection: Binding(
                        get: { state.transform.contourConfig.customColor },
                        set: { state.transform.contourConfig.customColor = $0 }
                    ))
                }

                LabeledSlider(
                    label: "Opacity",
                    value: Binding(
                        get: { state.transform.contourConfig.opacity },
                        set: { state.transform.contourConfig.opacity = $0 }
                    ),
                    range: 0...1,
                    step: 0.01,
                    displayFormat: { "\(Int($0 * 100))%" }
                )
            }
        }
    }
}
