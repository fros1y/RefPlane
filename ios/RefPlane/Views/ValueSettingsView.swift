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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bands")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Menu {
                        ForEach(distributePresets, id: \.self) { preset in
                            Button(preset.rawValue) {
                                applyDistribution(preset)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Distribute")
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                        }
                        .font(.footnote.weight(.medium))
                    }
                    .accessibilityIdentifier("studio.distribute-menu")
                }

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

    private var distributePresets: [ThresholdDistribution] {
        [.even, .shadows, .lights]
    }

    /// One-shot apply a distribution preset to the threshold handles.
    private func applyDistribution(_ distribution: ThresholdDistribution) {
        let bias: Double
        switch distribution {
        case .even, .custom: bias = 0
        case .shadows:       bias = 1
        case .lights:        bias = -1
        }
        state.transform.valueConfig.quantizationBias = bias
        state.transform.valueConfig.distribution = distribution
        state.transform.valueConfig.thresholds = distribution.thresholds(
            for: state.transform.valueConfig.levels
        )
        state.scheduleProcessing()
    }
}
