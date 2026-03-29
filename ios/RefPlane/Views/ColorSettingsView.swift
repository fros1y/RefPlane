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
                    }
                ),
                range: 2...6,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing {
                        state.triggerProcessing()
                    }
                }
            )

            LabeledSlider(
                label: "Values per Color",
                value: Binding(
                    get: { Double(state.colorConfig.valuesPerFamily) },
                    set: { newVal in
                        let values = Int(newVal.rounded())
                        state.colorConfig.valuesPerFamily = values
                        state.colorConfig.valueThresholds = defaultThresholds(for: values)
                    }
                ),
                range: 1...4,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing {
                        state.triggerProcessing()
                    }
                }
            )

            LabeledSlider(
                label: "Palette Spread",
                value: Binding(
                    get: { state.colorConfig.paletteSpread },
                    set: { state.colorConfig.paletteSpread = $0 }
                ),
                range: 0...1,
                step: 0.01,
                displayFormat: { value in
                    if value <= 0.01 { return "Mass" }
                    if value >= 0.99 { return "Hue" }
                    return String(format: "%.2f", value)
                },
                onEditingChanged: { editing in
                    if !editing {
                        state.triggerProcessing()
                    }
                }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Value Thresholds")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)

                ThresholdSliderView(
                    thresholds: Binding(
                        get: { state.colorConfig.valueThresholds },
                        set: { state.colorConfig.valueThresholds = $0 }
                    ),
                    levels: state.colorConfig.valuesPerFamily,
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
