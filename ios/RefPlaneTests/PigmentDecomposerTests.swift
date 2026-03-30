import Foundation
import Testing
@testable import Underpaint

@Suite
struct PigmentDecomposerTests {
    let database = SpectralDataStore.shared
    let allPigments = SpectralDataStore.essentialPigments

    @Test
    func tubeSelectionPicksHighestWeightedPigments() {
        guard allPigments.count >= 2 else { return }
        
        let recipes = [
            PigmentRecipe(components: [RecipeComponent(pigmentId: allPigments[0].id, pigmentName: "", concentration: 1.0)], predictedColor: OklabColor(L: 0.5, a: 0, b: 0), deltaE: 0),
            PigmentRecipe(components: [RecipeComponent(pigmentId: allPigments[1].id, pigmentName: "", concentration: 1.0)], predictedColor: OklabColor(L: 0.5, a: 0, b: 0), deltaE: 0)
        ]
        
        // Pixel counts favor recipe 1 heavily
        let selected = PigmentDecomposer.selectTubes(
            preliminaryRecipes: recipes,
            pixelCounts: [100, 10000],
            clusterSalience: [1.0, 1.0],
            maxTubes: 1,
            allPigments: allPigments,
            database: database
        )
        
        #expect(selected.count == 1)
        #expect(selected[0].id == allPigments[1].id)
    }
    
    @Test
    func mergeRecipesCombinesSimilarRecipes() {
        let c1 = RecipeComponent(pigmentId: "1", pigmentName: "A", concentration: 0.5)
        let r1 = PigmentRecipe(components: [c1], predictedColor: OklabColor(L: 0.5, a: 0.1, b: 0.1), deltaE: 0)
        let r2 = PigmentRecipe(components: [c1], predictedColor: OklabColor(L: 0.5, a: 0.1, b: 0.1), deltaE: 0)
        
        let (merged, map) = PigmentDecomposer.mergeRecipes(
            recipes: [r1, r2],
            pixelCounts: [100, 200],
            colorThreshold: 0.05,
            concentrationThreshold: 0.1
        )
        
        #expect(merged.count == 1)
        #expect(map == [0, 0])
    }
    
    @Test
    func mergeRecipesMergesOnColorMatchAlone() {
        // Two recipes with DIFFERENT pigment sets but nearly identical predicted colors
        let r1 = PigmentRecipe(
            components: [RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 1.0)],
            predictedColor: OklabColor(L: 0.5, a: 0.1, b: 0.1),
            deltaE: 0.01
        )
        let r2 = PigmentRecipe(
            components: [RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 1.0)],
            predictedColor: OklabColor(L: 0.501, a: 0.101, b: 0.101),
            deltaE: 0.01
        )

        let (merged, map) = PigmentDecomposer.mergeRecipes(
            recipes: [r1, r2],
            pixelCounts: [100, 200],
            colorThreshold: 0.05,
            concentrationThreshold: 0.05
        )

        #expect(merged.count == 1, "Recipes with different pigments but same color should merge")
        #expect(map == [0, 0])
    }

    @Test
    func mergeRecipesMergesOnStructureMatchAlone() {
        // Two recipes with SAME pigments and similar concentrations but colors beyond colorThreshold
        let r1 = PigmentRecipe(
            components: [
                RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 0.6),
                RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 0.4)
            ],
            predictedColor: OklabColor(L: 0.3, a: 0.1, b: 0.1),
            deltaE: 0.01
        )
        let r2 = PigmentRecipe(
            components: [
                RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 0.62),
                RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 0.38)
            ],
            predictedColor: OklabColor(L: 0.5, a: 0.2, b: 0.2),
            deltaE: 0.01
        )

        let (merged, map) = PigmentDecomposer.mergeRecipes(
            recipes: [r1, r2],
            pixelCounts: [100, 200],
            colorThreshold: 0.005, // Very tight color threshold — colors are far apart
            concentrationThreshold: 0.05
        )

        #expect(merged.count == 1, "Recipes with same pigments and similar concentrations should merge regardless of color distance")
        #expect(map == [0, 0])
    }

    @Test
    func mergeRecipesLargerClusterAbsorbsSmaller() {
        let r1 = PigmentRecipe(
            components: [RecipeComponent(pigmentId: "pigA", pigmentName: "A", concentration: 1.0)],
            predictedColor: OklabColor(L: 0.5, a: 0.1, b: 0.1),
            deltaE: 0.05
        )
        let r2 = PigmentRecipe(
            components: [RecipeComponent(pigmentId: "pigB", pigmentName: "B", concentration: 1.0)],
            predictedColor: OklabColor(L: 0.501, a: 0.101, b: 0.101),
            deltaE: 0.01
        )

        // r2 has more pixels (500 vs 100), so r2's recipe should be the survivor
        let (merged, map) = PigmentDecomposer.mergeRecipes(
            recipes: [r1, r2],
            pixelCounts: [100, 500],
            colorThreshold: 0.05,
            concentrationThreshold: 0.05
        )

        #expect(merged.count == 1)
        #expect(merged[0].components[0].pigmentId == "pigB", "Larger cluster's recipe should survive")
        #expect(map == [0, 0])
    }

    @Test
    func findBestRecipeRespectsMinConcentration() {
        let target = OklabColor(L: 0.5, a: 0.1, b: 0.1)
        
        // This implicitly calls findBestRecipe through decompose
        let recipes = PigmentDecomposer.decompose(
            targetColors: [target],
            pigments: allPigments,
            database: database,
            maxPigments: 3,
            minConcentration: 0.15 // High threshold
        )
        
        guard let recipe = recipes.first else {
            Issue.record("No recipe generated")
            return
        }
        
        for comp in recipe.components {
            #expect(comp.concentration >= 0.149) // minor float precision leeway
        }
    }
}
