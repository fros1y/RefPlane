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

                    if component.pigmentId == dominantPigmentID {
                        Text("Dominant")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }

                    Spacer()

                    Text(partsLabel(for: component.concentration))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(component.pigmentId == dominantPigmentID ? .primary : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    private var dominantPigmentID: String? {
        recipe.components.max(by: { $0.concentration < $1.concentration })?.pigmentId
    }

    private func partsLabel(for concentration: Float) -> String {
        let parts = max(1, Int((concentration * 8).rounded()))
        return parts == 1 ? "1 part" : "\(parts) parts"
    }
}
