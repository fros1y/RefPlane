import SwiftUI

struct DepthSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            Toggle("Depth Effects", isOn: Binding(
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

            if state.depthConfig.enabled {
                let range = state.depthRange
                let step = max(0.01, (range.upperBound - range.lowerBound) / 100.0)

                LabeledSlider(
                    label: "Foreground",
                    value: Binding(
                        get: { state.depthConfig.foregroundCutoff },
                        set: { newValue in
                            let clamped = min(newValue, state.depthConfig.backgroundCutoff - step)
                            guard clamped != state.depthConfig.foregroundCutoff else { return }
                            state.depthConfig.foregroundCutoff = clamped
                            state.updateDepthThresholdPreview()
                        }
                    ),
                    range: range.lowerBound...range.upperBound,
                    step: step,
                    displayFormat: { "\(Int(($0 - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))%" },
                    onEditingChanged: { editing in
                        if !editing {
                            state.dismissDepthThresholdPreview()
                        }
                    }
                )

                LabeledSlider(
                    label: "Background",
                    value: Binding(
                        get: { state.depthConfig.backgroundCutoff },
                        set: { newValue in
                            let clamped = max(newValue, state.depthConfig.foregroundCutoff + step)
                            guard clamped != state.depthConfig.backgroundCutoff else { return }
                            state.depthConfig.backgroundCutoff = clamped
                            state.updateDepthThresholdPreview()
                        }
                    ),
                    range: range.lowerBound...range.upperBound,
                    step: step,
                    displayFormat: { "\(Int(($0 - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))%" },
                    onEditingChanged: { editing in
                        if !editing {
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
                    label: "Intensity",
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
