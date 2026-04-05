import SwiftUI

struct DepthSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let range = state.depthRange
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        let step = max(0.01, span / 100.0)

        VStack(spacing: 14) {
            Picker("Adjust Background", selection: Binding(
                get: { state.depthConfig.backgroundMode },
                set: setBackgroundMode
            )) {
                ForEach(BackgroundMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("studio.background-mode-picker")

            if state.depthConfig.backgroundMode != .none {
                LabeledSlider(
                    label: "Depth Threshold",
                    value: Binding(
                        get: { state.depthConfig.backgroundCutoff },
                        set: { newValue in
                            state.updateBackgroundDepthCutoff(newValue)
                        }
                    ),
                    range: range.lowerBound...range.upperBound,
                    step: step,
                    displayFormat: { "\(Int(($0 - range.lowerBound) / span * 100))%" },
                    onEditingChanged: { editing in
                        state.depthSliderActive = editing
                        if editing {
                            state.updateDepthThresholdPreview()
                        } else {
                            state.dismissDepthThresholdPreview()
                        }
                    }
                )

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

            if let source = state.depthSource {
                Text(source == .embedded ? "Using Spatial depth" : "Using estimated depth")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("studio.depth-settings")
    }

    private func setBackgroundMode(_ newMode: BackgroundMode) {
        guard newMode != state.depthConfig.backgroundMode else { return }

        state.depthConfig.backgroundMode = newMode

        if newMode == .none {
            state.depthConfig.enabled = false
            state.dismissDepthThresholdPreview()
            return
        }

        state.depthConfig.enabled = true
        if state.depthMap == nil {
            state.computeDepthMap()
        } else {
            state.applyDepthEffects()
        }
    }
}
