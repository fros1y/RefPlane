import SwiftUI

struct RecipeView: View {
    let recipe: PigmentRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(recipe.components) { component in
                HStack(spacing: 8) {
                    Text(component.pigmentName)
                        .font(component.pigmentId == dominantPigmentID ? .footnote.weight(.semibold) : .footnote)
                        .foregroundStyle(component.pigmentId == dominantPigmentID ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    if showsPartsLabel {
                        let parts = simplifiedParts[component.pigmentId] ?? 1
                        Text(parts == 1 ? "1 part" : "\(parts) parts")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(component.pigmentId == dominantPigmentID ? .primary : .secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    private var dominantPigmentID: String? {
        recipe.dominantPigmentID
    }

    private var showsPartsLabel: Bool {
        recipe.components.count > 1
    }

    private var simplifiedParts: [String: Int] {
        recipe.simplifiedParts
    }
}
