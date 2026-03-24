import SwiftUI

struct ColorSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Value Bands
            LabeledSlider(
                label: "Value Bands",
                value: Binding(
                    get: { Double(state.colorConfig.bands) },
                    set: { newVal in
                        let bands = Int(newVal.rounded())
                        state.colorConfig.bands = bands
                        state.colorConfig.thresholds = defaultThresholds(for: bands)
                        state.triggerProcessing()
                    }
                ),
                range: 2...6,
                step: 1,
                displayFormat: { "\(Int($0))" }
            )

            // Colors per band
            LabeledSlider(
                label: "Colors / Band",
                value: Binding(
                    get: { Double(state.colorConfig.colorsPerBand) },
                    set: { newVal in
                        state.colorConfig.colorsPerBand = Int(newVal.rounded())
                        state.triggerProcessing()
                    }
                ),
                range: 1...4,
                step: 1,
                displayFormat: { "\(Int($0))" }
            )

            // Warm/cool emphasis
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

            // Band thresholds
            Text("Band Thresholds")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            ThresholdSliderView(
                thresholds: Binding(
                    get: { state.colorConfig.thresholds },
                    set: { state.colorConfig.thresholds = $0; state.triggerProcessing() }
                ),
                levels: state.colorConfig.bands,
                colorForLevel: { level, total in
                    let t = total > 1 ? Double(level) / Double(total - 1) : 0.5
                    return Color(white: t)
                }
            )

            // Min region size
            LabeledPicker(
                title: "Min Region",
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
