import SwiftUI

struct ValueSettingsView: View {
    @EnvironmentObject private var state: AppState

    private var config: ValueConfig {
        get { state.valueConfig }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Notan preset
            Button(action: applyNotan) {
                Text("Notan (2 levels)")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Levels slider
            LabeledSlider(
                label: "Levels",
                value: Binding(
                    get: { Double(state.valueConfig.levels) },
                    set: { newVal in
                        let lvl = Int(newVal.rounded())
                        state.valueConfig.levels = lvl
                        state.valueConfig.thresholds = defaultThresholds(for: lvl)
                        state.triggerProcessing()
                    }
                ),
                range: 2...8,
                step: 1,
                displayFormat: { "\(Int($0))" }
            )

            // Threshold sliders
            Text("Thresholds")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
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

            // Min region size
            LabeledPicker(
                title: "Min Region",
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
