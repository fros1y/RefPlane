import SwiftUI

struct ValueSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            LabeledSlider(
                label: "Values",
                value: Binding(
                    get: { Double(state.valueConfig.levels) },
                    set: { newVal in
                        let level = Int(newVal.rounded())
                        state.valueConfig.levels = level
                        state.valueConfig.thresholds = state.valueConfig.distribution.thresholds(for: level)
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

            Picker("Band Bias", selection: Binding(
                get: { state.valueConfig.distribution },
                set: { newDist in
                    state.valueConfig.distribution = newDist
                    if newDist != .custom {
                        state.valueConfig.thresholds = newDist.thresholds(for: state.valueConfig.levels)
                        state.scheduleProcessing()
                    }
                }
            )) {
                ForEach(ThresholdDistribution.allCases) { dist in
                    Text(dist.rawValue).tag(dist)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Thresholds")
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
                    onEditingEnded: {
                        state.scheduleProcessing()
                    }
                )
            }
        }
    }
}
