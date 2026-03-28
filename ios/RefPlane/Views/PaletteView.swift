import SwiftUI

struct PaletteView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            let sections = PaletteSections.makeSections(
                paletteBands: state.paletteBands,
                paletteCount: state.paletteColors.count
            )

            if sections.isEmpty {
                Text("Palette swatches appear after you generate a value or color study.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections, id: \.band) { section in
                    Button {
                        state.toggleIsolatedBand(section.band)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Band \(section.band + 1)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .leading)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(section.indices, id: \.self) { idx in
                                        let color = state.paletteColors[idx]
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(color)
                                            .frame(width: 36, height: 28)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        state.isolatedBand == section.band
                                                            ? Color.accentColor
                                                            : Color(.separator),
                                                        lineWidth: state.isolatedBand == section.band ? 2 : 1
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
                    .accessibilityLabel("Palette band \(section.band + 1), \(section.indices.count) color\(section.indices.count == 1 ? "" : "s")")
                    .accessibilityValue(state.isolatedBand == section.band ? "Isolated" : "")
                    .accessibilityHint(state.isolatedBand == section.band ? "Tap to show all bands" : "Tap to isolate this band")
                }
            }
        }
    }
}
