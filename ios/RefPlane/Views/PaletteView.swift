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
                let sorted = sortedSections(sections)

                ForEach(Array(sorted.enumerated()), id: \.offset) { mixNum, section in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            state.toggleIsolatedBand(section.band)
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Text("Mix \(mixNum + 1)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .leading)

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
                        .accessibilityLabel("Mix \(mixNum + 1), \(section.indices.count) color\(section.indices.count == 1 ? "" : "s")")
                        .accessibilityValue(state.isolatedBand == section.band ? "Isolated" : "")
                        .accessibilityHint(state.isolatedBand == section.band ? "Tap to show all mixes" : "Tap to isolate this mix")

                        if let recipes = state.pigmentRecipes {
                            ForEach(section.indices, id: \.self) { idx in
                                if idx < recipes.count {
                                    RecipeView(recipe: recipes[idx])
                                        .padding(.leading, 66)
                                        .padding(.bottom, 2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Sort sections by the name of the majority (highest-concentration) pigment in the first recipe.
    private func sortedSections(_ sections: [PaletteBandSection]) -> [PaletteBandSection] {
        guard let recipes = state.pigmentRecipes else { return sections }
        return sections.sorted { a, b in
            let nameA = majorityPigmentName(for: a, recipes: recipes)
            let nameB = majorityPigmentName(for: b, recipes: recipes)
            return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
        }
    }

    private func majorityPigmentName(for section: PaletteBandSection, recipes: [PigmentRecipe]) -> String {
        guard let firstIdx = section.indices.first,
              firstIdx < recipes.count,
              let top = recipes[firstIdx].components.max(by: { $0.concentration < $1.concentration })
        else { return "" }
        return top.pigmentName
    }
}
