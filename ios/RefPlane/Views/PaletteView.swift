import SwiftUI

struct PaletteView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            let maxBand = state.paletteBands.max() ?? -1

            if maxBand < 0 {
                Text("Palette swatches appear after you generate a value or color study.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(0...maxBand, id: \.self) { band in
                    let indices = state.paletteBands.enumerated()
                        .filter { $0.element == band }
                        .map { $0.offset }

                    if !indices.isEmpty {
                        Button {
                            state.isolatedBand = state.isolatedBand == band ? nil : band
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Text("Band \(band + 1)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 64, alignment: .leading)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(indices, id: \.self) { idx in
                                            let color = state.paletteColors[idx]
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(color)
                                                .frame(width: 36, height: 28)
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(
                                                            state.isolatedBand == band
                                                                ? Color.accentColor
                                                                : Color(.separator),
                                                            lineWidth: state.isolatedBand == band ? 2 : 1
                                                        )
                                                }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Palette band \(band + 1)")
                        .accessibilityValue(state.isolatedBand == band ? "Selected" : "Not selected")
                    }
                }
            }
        }
    }
}
