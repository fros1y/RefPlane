import SwiftUI

struct ValueSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            LabeledSlider(
                label: "Count",
                value: Binding(
                    get: { Double(state.transform.valueConfig.levels) },
                    set: { newVal in
                        let level = Int(newVal.rounded())
                        state.transform.valueConfig.levels = level
                        state.transform.valueConfig.thresholds = QuantizationBias.thresholds(
                            for: level,
                            bias: state.transform.valueConfig.quantizationBias
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
                    get: { state.transform.valueConfig.quantizationBias },
                    set: { newBias in
                        let clampedBias = QuantizationBias.clamped(newBias)
                        state.transform.valueConfig.quantizationBias = clampedBias
                        state.transform.valueConfig.distribution = QuantizationBias.distribution(
                            for: clampedBias
                        )
                        state.transform.valueConfig.thresholds = QuantizationBias.thresholds(
                            for: state.transform.valueConfig.levels,
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
                        get: { state.transform.valueConfig.thresholds },
                        set: {
                            state.transform.valueConfig.thresholds = $0
                            // Any manual adjustment switches to Custom
                            if state.transform.valueConfig.distribution != .custom {
                                state.transform.valueConfig.distribution = .custom
                            }
                        }
                    ),
                    levels: state.transform.valueConfig.levels,
                    colorForLevel: { level, total in
                        let t = total > 1 ? Double(level) / Double(total - 1) : 0.5
                        return Color(white: t)
                    },
                    onEditingChanged: state.pipeline.sliderEditingChanged,
                    onEditingEnded: {
                        state.scheduleProcessing()
                    }
                )
            }
        }
    }
}
