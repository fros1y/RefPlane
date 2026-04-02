import SwiftUI

struct DepthSettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var intensityAtDragStart: Double? = nil

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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Depth Zones")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)

                    ThresholdSliderView(
                        thresholds: Binding(
                            get: { [state.depthConfig.foregroundCutoff, state.depthConfig.backgroundCutoff] },
                            set: { newThresholds in
                                guard newThresholds.count >= 2 else { return }
                                state.depthConfig.foregroundCutoff = newThresholds[0]
                                state.depthConfig.backgroundCutoff = newThresholds[1]
                            }
                        ),
                        levels: 3,
                        colorForLevel: { level, _ in
                            switch level {
                            case 0:  return Color.orange.opacity(0.8)   // foreground (warm)
                            case 1:  return Color.gray.opacity(0.5)     // midground
                            default: return Color.blue.opacity(0.6)     // background (cool)
                            }
                        },
                        onEditingEnded: {
                            state.applyDepthEffects()
                        }
                    )
                }

                Picker("Background", selection: Binding(
                    get: { state.depthConfig.backgroundMode },
                    set: { newMode in
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
