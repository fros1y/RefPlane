import SwiftUI

struct DepthSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var settingsExpanded = false

    var body: some View {
        Group {
            Toggle("On", isOn: Binding(
                get: { state.depthConfig.enabled },
                set: { newValue in
                    state.depthConfig.enabled = newValue
                    if newValue {
                        state.computeDepthMap()
                    } else {
                        state.resetDepthProcessing()
                    }
                }
            ))
            .accessibilityLabel("Process Background")

            if state.depthConfig.enabled {
                DisclosureGroup("Settings", isExpanded: $settingsExpanded) {
                    let range = state.depthRange
                    let step = max(0.01, (range.upperBound - range.lowerBound) / 100.0)

                    VStack(spacing: 14) {
                        LabeledSlider(
                            label: "Split",
                            value: Binding(
                                get: { state.depthConfig.backgroundCutoff },
                                set: { newValue in
                                    state.updateBackgroundDepthCutoff(newValue)
                                }
                            ),
                            range: range.lowerBound...range.upperBound,
                            step: step,
                            displayFormat: { "\(Int(($0 - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))%" },
                            onEditingChanged: { editing in
                                state.depthSliderActive = editing
                                if editing {
                                    state.updateDepthThresholdPreview()
                                } else {
                                    state.dismissDepthThresholdPreview()
                                }
                            }
                        )

                        Picker("Background", selection: Binding(
                            get: { state.depthConfig.backgroundMode },
                            set: { newMode in
                                guard newMode != state.depthConfig.backgroundMode else { return }
                                state.depthConfig.backgroundMode = newMode
                                state.applyDepthEffects()
                            }
                        )) {
                            ForEach(BackgroundMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        LabeledSlider(
                            label: "Amount",
                            value: Binding(
                                get: { state.depthConfig.effectIntensity },
                                set: { state.depthConfig.effectIntensity = $0 }
                            ),
                            range: 0...1,
                            step: 0.05,
                            displayFormat: { "\(Int($0 * 100))%" },
                            onEditingChanged: { editing in
                                if !editing {
                                    state.applyDepthEffects()
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}
