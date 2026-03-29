import SwiftUI

struct ValueSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            LabeledSlider(
                label: "Levels",
                value: Binding(
                    get: { Double(state.valueConfig.levels) },
                    set: { newVal in
                        let level = Int(newVal.rounded())
                        state.valueConfig.levels = level
                        state.valueConfig.thresholds = defaultThresholds(for: level)
                    }
                ),
                range: 2...8,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing {
                        state.triggerProcessing()
                    }
                }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Thresholds")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)

                ThresholdSliderView(
                    thresholds: Binding(
                        get: { state.valueConfig.thresholds },
                        set: { state.valueConfig.thresholds = $0 }
                    ),
                    levels: state.valueConfig.levels,
                    colorForLevel: { level, total in
                        let t = total > 1 ? Double(level) / Double(total - 1) : 0.5
                        return Color(white: t)
                    },
                    onEditingEnded: {
                        state.triggerProcessing()
                    }
                )
            }
        }
    }
}
