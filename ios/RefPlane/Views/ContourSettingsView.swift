import SwiftUI

struct ContourSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            Toggle("Surface Contours", isOn: Binding(
                get: { state.contourConfig.enabled },
                set: { newValue in
                    state.contourConfig.enabled = newValue
                    if newValue {
                        state.recomputeContours()
                    } else {
                        state.contourSegments = []
                    }
                }
            ))

            if state.contourConfig.enabled {
                LabeledPicker(
                    title: "Contour Mode",
                    selection: Binding(
                        get: { state.contourConfig.mode },
                        set: { newMode in
                            state.contourConfig.mode = newMode
                            state.recomputeContours()
                        }
                    ),
                    options: ContourMode.allCases,
                    label: { $0.rawValue }
                )

                LabeledSlider(
                    label: "Levels",
                    value: Binding(
                        get: { Double(state.contourConfig.levels) },
                        set: { state.contourConfig.levels = Int($0.rounded()) }
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

                if state.contourConfig.mode == .isolines {
                    Toggle("Orthogonal Lines", isOn: Binding(
                        get: { state.contourConfig.showOrthogonal },
                        set: { newValue in
                            state.contourConfig.showOrthogonal = newValue
                            state.recomputeContours()
                        }
                    ))
                } else {
                    LabeledSlider(
                        label: "Depth Scale",
                        value: Binding(
                            get: { state.contourConfig.depthScale },
                            set: { state.contourConfig.depthScale = $0 }
                        ),
                        range: 0...12,
                        step: 0.1,
                        displayFormat: { String(format: "%.1f×", $0) },
                        onEditingChanged: { editing in
                            if !editing {
                                state.recomputeContours()
                            }
                        }
                    )
                }

                LabeledPicker(
                    title: "Line Style",
                    selection: Binding(
                        get: { state.contourConfig.lineStyle },
                        set: { state.contourConfig.lineStyle = $0 }
                    ),
                    options: LineStyle.allCases,
                    label: { $0.rawValue }
                )

                if state.contourConfig.lineStyle == .custom {
                    ColorPicker("Color", selection: Binding(
                        get: { state.contourConfig.customColor },
                        set: { state.contourConfig.customColor = $0 }
                    ))
                }

                LabeledSlider(
                    label: "Opacity",
                    value: Binding(
                        get: { state.contourConfig.opacity },
                        set: { state.contourConfig.opacity = $0 }
                    ),
                    range: 0...1,
                    step: 0.01,
                    displayFormat: { "\(Int($0 * 100))%" }
                )
            }
        }
    }
}
