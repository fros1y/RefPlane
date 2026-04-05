import SwiftUI

struct ValueSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            LabeledSlider(
                label: "Count",
                value: Binding(
                    get: { Double(state.valueConfig.levels) },
                    set: { newVal in
                        let level = Int(newVal.rounded())
                        state.valueConfig.levels = level
                        state.valueConfig.thresholds = QuantizationBias.thresholds(
                            for: level,
                            bias: state.valueConfig.quantizationBias
                        )
                    }
                ),
                range: 2...16,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing {
                        state.scheduleProcessing()
                    }
                }
            )

            QuantizationBiasSlider(
                value: Binding(
                    get: { state.valueConfig.quantizationBias },
                    set: { newBias in
                        let clampedBias = QuantizationBias.clamped(newBias)
                        state.valueConfig.quantizationBias = clampedBias
                        state.valueConfig.distribution = QuantizationBias.distribution(
                            for: clampedBias
                        )
                        state.valueConfig.thresholds = QuantizationBias.thresholds(
                            for: state.valueConfig.levels,
                            bias: clampedBias
                        )
                    }
                ),
                onEditingChanged: { editing in
                    if !editing {
                        state.scheduleProcessing()
                    }
                }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Bands")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)

                ThresholdSliderView(
                    thresholds: Binding(
                        get: { state.valueConfig.thresholds },
                        set: {
                            state.valueConfig.thresholds = $0
                            // Any manual adjustment switches to Custom
                            if state.valueConfig.distribution != .custom {
                                state.valueConfig.distribution = .custom
                            }
                        }
                    ),
                    levels: state.valueConfig.levels,
                    colorForLevel: { level, total in
                        let t = total > 1 ? Double(level) / Double(total - 1) : 0.5
                        return Color(white: t)
                    },
                    onEditingChanged: state.sliderEditingChanged,
                    onEditingEnded: {
                        state.scheduleProcessing()
                    }
                )
            }
        }
    }
}
