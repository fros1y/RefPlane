import SwiftUI

struct PaletteView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let sections = sortedSections(
            PaletteSections.makeSections(
                paletteBands: state.paletteBands,
                paletteCount: state.paletteColors.count
            )
        )

        if sections.isEmpty {
            Text("No swatches yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 12) {
                ForEach(sections, id: \.band) { section in
                    PaletteMixCard(
                        bandID: section.band,
                        title: title(for: section),
                        section: section,
                        colors: colors(for: section),
                        recipes: recipes(for: section),
                        isFocused: state.focusedBands.contains(section.band),
                        onToggleFocus: { state.toggleFocusedBand(section.band) }
                    )
                }
            }
        }
    }

    private func colors(for section: PaletteBandSection) -> [Color] {
        section.indices.compactMap { index in
            guard state.paletteColors.indices.contains(index) else { return nil }
            return state.paletteColors[index]
        }
    }

    private func recipes(for section: PaletteBandSection) -> [PigmentRecipe] {
        guard let pigmentRecipes = state.pigmentRecipes else { return [] }
        return section.indices.compactMap { index in
            guard pigmentRecipes.indices.contains(index) else { return nil }
            return pigmentRecipes[index]
        }
    }

    private func sortedSections(_ sections: [PaletteBandSection]) -> [PaletteBandSection] {
        return sections.sorted { lhs, rhs in
            let nameA = title(for: lhs)
            let nameB = title(for: rhs)
            let comparison = nameA.localizedCaseInsensitiveCompare(nameB)
            if comparison == .orderedSame {
                return lhs.band < rhs.band
            }
            return comparison == .orderedAscending
        }
    }

    private func title(for section: PaletteBandSection) -> String {
        guard let firstIndex = section.indices.first else {
            return "Swatch"
        }

        if state.paletteColors.indices.contains(firstIndex),
           let name = PaletteColorNamer.name(for: state.paletteColors[firstIndex]) {
            return name
        }

        if let pigmentRecipes = state.pigmentRecipes,
           pigmentRecipes.indices.contains(firstIndex) {
            return PaletteColorNamer.name(for: pigmentRecipes[firstIndex].predictedColor)
        }

        return "Swatch"
    }
}

private struct PaletteMixCard: View {
    let bandID: Int
    let title: String
    let section: PaletteBandSection
    let colors: [Color]
    let recipes: [PigmentRecipe]
    let isFocused: Bool
    let onToggleFocus: () -> Void

    var body: some View {
        Button(action: onToggleFocus) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    FocusPill(isFocused: isFocused)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(color)
                                .frame(width: 52, height: 44)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            isFocused ? Color.accentColor : Color(.separator),
                                            lineWidth: isFocused ? 2 : 1
                                        )
                                }
                        }
                    }
                }

                if !recipes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(recipes.enumerated()), id: \.offset) { _, recipe in
                            RecipeView(recipe: recipe)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                isFocused
                    ? Color.accentColor.opacity(0.08)
                    : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isFocused ? "Focused on canvas" : "Showing all mixes")
        .accessibilityHint(isFocused ? "Double tap to remove focus from this mix" : "Double tap to focus this mix")
        .accessibilityIdentifier("mix-card.\(bandID)")
    }
}

struct FocusPill: View {
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isFocused ? "scope" : "circle.dashed")
            Text(isFocused ? "Focused" : "Focus")
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isFocused ? Color.accentColor : Color.primary.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isFocused
                ? Color.accentColor.opacity(0.12)
                : Color.primary.opacity(0.05),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    isFocused
                        ? Color.accentColor.opacity(0.35)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct PalettePreviewHarness: View {
    @State private var state = AppState()

    init() {
        let previewState = AppState()
        previewState.activeMode = .color
        previewState.paletteColors = [
            Color(red: 0.74, green: 0.23, blue: 0.17),
            Color(red: 0.93, green: 0.80, blue: 0.53),
            Color(red: 0.19, green: 0.31, blue: 0.56),
            Color(red: 0.92, green: 0.91, blue: 0.88),
        ]
        previewState.paletteBands = [0, 0, 1, 1]
        previewState.pigmentRecipes = [
            PigmentRecipe(
                components: [
                    RecipeComponent(pigmentId: "cad_red_medium", pigmentName: "Cad Red Medium", concentration: 0.72),
                    RecipeComponent(pigmentId: "yellow_ochre", pigmentName: "Yellow Ochre", concentration: 0.28),
                ],
                predictedColor: OklabColor(L: 0.62, a: 0.12, b: 0.08),
                deltaE: 1.3
            ),
            PigmentRecipe(
                components: [
                    RecipeComponent(pigmentId: "yellow_ochre", pigmentName: "Yellow Ochre", concentration: 0.58),
                    RecipeComponent(pigmentId: "titanium_white", pigmentName: "Titanium White", concentration: 0.42),
                ],
                predictedColor: OklabColor(L: 0.84, a: 0.01, b: 0.09),
                deltaE: 0.8
            ),
            PigmentRecipe(
                components: [
                    RecipeComponent(pigmentId: "ultramarine_blue", pigmentName: "Ultramarine Blue", concentration: 0.66),
                    RecipeComponent(pigmentId: "carbon_black", pigmentName: "Carbon Black", concentration: 0.34),
                ],
                predictedColor: OklabColor(L: 0.38, a: -0.02, b: -0.12),
                deltaE: 2.0
            ),
            PigmentRecipe(
                components: [
                    RecipeComponent(pigmentId: "titanium_white", pigmentName: "Titanium White", concentration: 0.90),
                    RecipeComponent(pigmentId: "yellow_ochre", pigmentName: "Yellow Ochre", concentration: 0.10),
                ],
                predictedColor: OklabColor(L: 0.95, a: 0.0, b: 0.02),
                deltaE: 0.5
            ),
        ]
        previewState.focusedBands = [0]
        _state = State(initialValue: previewState)
    }

    var body: some View {
        ScrollView {
            PaletteView()
                .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .environment(state)
    }
}

#Preview("Palette") {
    PalettePreviewHarness()
}
