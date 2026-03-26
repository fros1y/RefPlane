import SwiftUI

struct ColorSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            LabeledSlider(
                label: "Color Families",
                value: Binding(
                    get: { Double(state.colorConfig.colorFamilies) },
                    set: { newVal in
                        state.colorConfig.colorFamilies = Int(newVal.rounded())
                        state.triggerProcessing()
                    }
                ),
                range: 2...6,
                step: 1,
                displayFormat: { "\(Int($0))" }
            )

            LabeledSlider(
                label: "Values per Color",
                value: Binding(
                    get: { Double(state.colorConfig.valuesPerFamily) },
                    set: { newVal in
                        let values = Int(newVal.rounded())
                        state.colorConfig.valuesPerFamily = values
                        state.colorConfig.valueThresholds = defaultThresholds(for: values)
                        state.triggerProcessing()
                    }
                ),
                range: 1...4,
                step: 1,
                displayFormat: { "\(Int($0))" }
            )

            LabeledSlider(
                label: "Warm/Cool",
                value: Binding(
                    get: { state.colorConfig.warmCoolEmphasis },
                    set: { state.colorConfig.warmCoolEmphasis = $0; state.triggerProcessing() }
                ),
                range: -1...1,
                step: 0.01,
                displayFormat: { String(format: "%.2f", $0) }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Value Thresholds")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                ThresholdSliderView(
                    thresholds: Binding(
                        get: { state.colorConfig.valueThresholds },
                        set: { state.colorConfig.valueThresholds = $0; state.triggerProcessing() }
                    ),
                    levels: state.colorConfig.valuesPerFamily,
                    colorForLevel: { level, total in
                        let t = total > 1 ? Double(level) / Double(total - 1) : 0.5
                        return Color(white: t)
                    }
                )
            }

            LabeledPicker(
                title: "Minimum Region",
                selection: Binding(
                    get: { state.colorConfig.minRegionSize },
                    set: { state.colorConfig.minRegionSize = $0; state.triggerProcessing() }
                ),
                options: MinRegionSize.allCases,
                label: { $0.rawValue }
            )
        }
    }
}
