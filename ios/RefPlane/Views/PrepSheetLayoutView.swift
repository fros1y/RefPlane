import SwiftUI

/// Fixed single-page layout for the exported Prep Sheet. Sized in points
/// (1 pt = 1/72 in) so absolute font sizes map directly to print sizes.
struct PrepSheetLayoutView: View {
    let content: PrepSheetContent
    let pageSize: CGSize

    private let margin: CGFloat = 36
    private let panelSpacing: CGFloat = 14
    private let maxRecipeRows = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: panelSpacing) {
                panel(
                    image: content.referenceImage,
                    title: "REFERENCE",
                    caption: nil
                )
                panel(
                    image: content.valueImage,
                    title: "VALUE STUDY",
                    caption: "\(content.valueLevels) values · \(content.valueDistributionName)"
                )
            }

            HStack(alignment: .top, spacing: panelSpacing) {
                panel(
                    image: content.colorImage,
                    title: "COLOR STUDY",
                    caption: colorCaption
                )
                paletteBlock
                    .frame(width: panelWidth)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(margin)
        .frame(width: pageSize.width, height: pageSize.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Metrics

    private var panelWidth: CGFloat {
        (pageSize.width - margin * 2 - panelSpacing) / 2
    }

    private var panelImageHeight: CGFloat {
        // Two rows of panels share the page with header, captions, and footer.
        (pageSize.height - margin * 2 - 200) / 2
    }

    private var colorCaption: String {
        if content.usesPigments {
            let mixCount = content.pigmentRecipes?.count ?? 0
            return "\(mixCount) pigment-mixed colors"
        }
        return "\(content.colorCount) colors"
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("UNDERPAINT")
                .font(.system(size: 13, weight: .bold))
                .kerning(2.4)
                .foregroundStyle(.black)

            Text("Painter's Prep Sheet")
                .font(.system(size: 9))
                .foregroundStyle(.gray)

            Spacer()

            Text(content.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 9))
                .foregroundStyle(.gray)
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.8))
                .frame(height: 0.7)
        }
    }

    private func panel(image: UIImage, title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: panelWidth, height: panelImageHeight)
                .background(Color(white: 0.96))
                .overlay {
                    Rectangle()
                        .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 7.5, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.black)

                if let caption {
                    Text(caption)
                        .font(.system(size: 7.5))
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private var paletteBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(content.usesPigments ? "PALETTE + RECIPES" : "PALETTE")
                .font(.system(size: 7.5, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.black)

            if content.usesPigments, let recipes = content.pigmentRecipes, !recipes.isEmpty {
                recipeRows(recipes)
            } else {
                swatchGrid
            }
        }
        .frame(maxHeight: panelImageHeight + 16, alignment: .top)
    }

    private func recipeRows(_ recipes: [PigmentRecipe]) -> some View {
        VStack(alignment: .leading, spacing: 3.5) {
            ForEach(Array(recipes.prefix(maxRecipeRows).enumerated()), id: \.offset) { index, recipe in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Circle()
                        .fill(swatchColor(at: index))
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.4)
                        }
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center] + 3
                        }

                    Text(recipeDescription(recipe))
                        .font(.system(size: 7.5))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                }
            }

            if recipes.count > maxRecipeRows {
                Text("+ \(recipes.count - maxRecipeRows) more mixes in the app")
                    .font(.system(size: 7))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var swatchGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(22), spacing: 5), count: 8)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(Array(content.paletteColors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 22, height: 16)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.4)
                    }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(content.usesPigments
                 ? "Kubelka–Munk mixing · Golden Heavy Body Acrylics"
                 : "Values and colors quantized in Oklab")
                .font(.system(size: 7))
                .foregroundStyle(.gray)

            Spacer()

            Text("Made with Underpaint")
                .font(.system(size: 7))
                .foregroundStyle(.gray)
        }
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    private func swatchColor(at index: Int) -> Color {
        guard content.paletteColors.indices.contains(index) else {
            return Color(white: 0.9)
        }
        return content.paletteColors[index]
    }

    /// "Cad Red Medium 3 · Yellow Ochre 1" — parts ordered by concentration.
    private func recipeDescription(_ recipe: PigmentRecipe) -> String {
        let parts = recipe.simplifiedParts
        let ordered = recipe.components.sorted { $0.concentration > $1.concentration }

        if ordered.count == 1, let only = ordered.first {
            return only.pigmentName
        }

        return ordered
            .map { component in
                "\(component.pigmentName) \(parts[component.pigmentId] ?? 1)"
            }
            .joined(separator: " · ")
    }
}

#Preview("Prep Sheet (Letter)") {
    let swatch: (CGFloat, CGFloat, CGFloat) -> UIImage = { r, g, b in
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240)).image { ctx in
            UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }
    }

    return PrepSheetLayoutView(
        content: PrepSheetContent(
            referenceImage: swatch(0.8, 0.7, 0.6),
            valueImage: swatch(0.5, 0.5, 0.5),
            colorImage: swatch(0.7, 0.5, 0.4),
            paletteColors: [
                Color(red: 0.74, green: 0.23, blue: 0.17),
                Color(red: 0.93, green: 0.80, blue: 0.53),
                Color(red: 0.19, green: 0.31, blue: 0.56),
            ],
            pigmentRecipes: [
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
            ],
            valueLevels: 5,
            valueDistributionName: "Shadow Detail",
            colorCount: 12,
            usesPigments: true
        ),
        pageSize: CGSize(width: 612, height: 792)
    )
}
