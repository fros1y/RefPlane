import SwiftUI

struct SimplificationSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            Toggle("Simplify Output", isOn: Binding(
                get: { state.simplificationConfig.enabled },
                set: { isEnabled in
                    state.simplificationConfig.enabled = isEnabled
                    state.triggerProcessing()
                }
            ))

            if state.simplificationConfig.enabled {
                LabeledPicker(
                    title: "Method",
                    selection: Binding(
                        get: { state.simplificationConfig.method },
                        set: { method in
                            state.simplificationConfig.method = method
                            state.triggerProcessing()
                        }
                    ),
                    options: SimplificationMethod.allCases,
                    label: { $0.rawValue }
                )

                switch state.simplificationConfig.method {
                case .regionCompaction:
                    LabeledPicker(
                        title: "Minimum Region",
                        selection: Binding(
                            get: { state.simplificationConfig.minRegionSize },
                            set: { minRegionSize in
                                state.simplificationConfig.minRegionSize = minRegionSize
                                state.triggerProcessing()
                            }
                        ),
                        options: MinRegionSize.allCases,
                        label: { $0.rawValue }
                    )

                case .kuwahara:
                    LabeledSlider(
                        label: "Radius",
                        value: Binding(
                            get: { Double(state.simplificationConfig.kuwaharaRadius) },
                            set: { radius in
                                state.simplificationConfig.kuwaharaRadius = Int(radius.rounded())
                                state.triggerProcessing()
                            }
                        ),
                        range: 2...12,
                        step: 1,
                        displayFormat: { "\(Int($0))" }
                    )
                }
            }
        }
    }
}
