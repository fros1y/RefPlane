import SwiftUI

struct RecipeView: View {
    let recipe: PigmentRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(recipe.components) { component in
                HStack(spacing: 8) {
                    Text(component.pigmentName)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int((component.concentration * 8).rounded()))/8")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }
}
