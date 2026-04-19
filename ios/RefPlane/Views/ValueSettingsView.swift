import SwiftUI

struct ValueSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            LabeledSlider(
                label: "Count",
                value: Binding(
                    get: { Double(state.transform.valueConfig.levels) },
                    set: { newVal in
                        let level = Int(newVal.rounded())
                        state.transform.valueConfig.levels = level
                        syncThresholdsForCurrentDistribution(levels: level)
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

            distributionMenu

            VStack(alignment: .leading, spacing: 8) {
                Text("Bands")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)

                ThresholdSliderView(
                    thresholds: Binding(
                        get: { state.transform.valueConfig.thresholds },
                        set: {
                            state.transform.valueConfig.thresholds = ThresholdUtilities.sanitized(
                                $0,
                                levels: state.transform.valueConfig.levels
                            )
                            // Any manual adjustment switches to Custom
                            if state.transform.valueConfig.distribution != .custom {
                                state.transform.valueConfig.distribution = .custom
                            }
                            state.transform.valueConfig.quantizationBias = 0
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

    private var distributionMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distribute")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)

            Menu {
                ForEach(ThresholdDistribution.allCases) { distribution in
                    Button {
                        applyDistribution(distribution)
                    } label: {
                        if distribution == state.transform.valueConfig.distribution {
                            Label(distribution.rawValue, systemImage: "checkmark")
                        } else {
                            Text(distribution.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(state.transform.valueConfig.distribution.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
        }
    }

    private func applyDistribution(_ distribution: ThresholdDistribution) {
        state.transform.valueConfig.distribution = distribution
        syncThresholdsForCurrentDistribution(levels: state.transform.valueConfig.levels)

        switch distribution {
        case .even:
            state.transform.valueConfig.quantizationBias = 0
        case .shadows:
            state.transform.valueConfig.quantizationBias = 1
        case .lights:
            state.transform.valueConfig.quantizationBias = -1
        case .custom:
            break
        }

        state.scheduleProcessing()
    }

    private func syncThresholdsForCurrentDistribution(levels: Int) {
        let distribution = state.transform.valueConfig.distribution
        guard distribution != .custom else {
            state.transform.valueConfig.thresholds = ThresholdUtilities.sanitized(
                state.transform.valueConfig.thresholds,
                levels: levels
            )
            return
        }

        state.transform.valueConfig.thresholds = distribution.thresholds(for: levels)
    }
}
