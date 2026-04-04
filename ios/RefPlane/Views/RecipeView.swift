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

                    Spacer()

                    if showsPartsLabel {
                        let parts = simplifiedParts[component.pigmentId] ?? 1
                        Text(parts == 1 ? "1 part" : "\(parts) parts")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(component.pigmentId == dominantPigmentID ? .primary : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    private var dominantPigmentID: String? {
        recipe.components.max(by: { $0.concentration < $1.concentration })?.pigmentId
    }

    private var showsPartsLabel: Bool {
        recipe.components.count > 1
    }

    private var simplifiedParts: [String: Int] {
        let rawParts = recipe.components.map { component in
            (pigmentId: component.pigmentId, parts: max(1, Int((component.concentration * 8).rounded())))
        }
        let divisor = rawParts
            .map(\.parts)
            .reduce(0) { current, parts in
                current == 0 ? parts : greatestCommonDivisor(current, parts)
            }

        return rawParts.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.pigmentId] = entry.parts / max(1, divisor)
        }
    }

    private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var left = abs(lhs)
        var right = abs(rhs)

        while right != 0 {
            let remainder = left % right
            left = right
            right = remainder
        }

        return max(1, left)
    }
}
