import SwiftUI

struct ValueSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            Button("Apply Notan") {
                applyNotan()
            }
            .buttonStyle(.bordered)

            LabeledSlider(
                label: "Levels",
                value: Binding(
                    get: { Double(state.valueConfig.levels) },
                    set: { newVal in
                        let level = Int(newVal.rounded())
                        state.valueConfig.levels = level
                        state.valueConfig.thresholds = defaultThresholds(for: level)
                        state.triggerProcessing()
                    }
                ),
                range: 2...8,
                step: 1,
                displayFormat: { "\(Int($0))" }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Thresholds")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                ThresholdSliderView(
                    thresholds: Binding(
                        get: { state.valueConfig.thresholds },
                        set: { state.valueConfig.thresholds = $0; state.triggerProcessing() }
                    ),
                    levels: state.valueConfig.levels,
                    colorForLevel: { level, total in
                        let t = total > 1 ? Float(level) / Float(total - 1) : 0.5
                        return Color(white: Double(t))
                    }
                )
            }

            LabeledPicker(
                title: "Minimum Region",
                selection: Binding(
                    get: { state.valueConfig.minRegionSize },
                    set: { state.valueConfig.minRegionSize = $0; state.triggerProcessing() }
                ),
                options: MinRegionSize.allCases,
                label: { $0.rawValue }
            )
        }
    }

    private func applyNotan() {
        state.valueConfig.levels = 2
        state.valueConfig.thresholds = [0.5]
        state.triggerProcessing()
    }
}
