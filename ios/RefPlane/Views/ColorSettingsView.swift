import SwiftUI

struct ColorSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            LabeledSlider(
                label: "Shades",
                value: Binding(
                    get: { Double(state.colorConfig.numShades) },
                    set: { state.colorConfig.numShades = Int($0.rounded()) }
                ),
                range: 2...24,
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

            Divider()

            LabeledSlider(
                label: "Tubes",
                value: Binding(
                    get: { Double(state.colorConfig.numTubes) },
                    set: { state.colorConfig.numTubes = Int($0.rounded()) }
                ),
                range: 3...10,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing { state.triggerProcessing() }
                }
            )

            LabeledSlider(
                label: "Max Pigments",
                value: Binding(
                    get: { Double(state.colorConfig.maxPigmentsPerMix) },
                    set: { state.colorConfig.maxPigmentsPerMix = Int($0.rounded()) }
                ),
                range: 1...3,
                step: 1,
                displayFormat: { "\(Int($0))" },
                onEditingChanged: { editing in
                    if !editing { state.triggerProcessing() }
                }
            )
        }
    }
}
