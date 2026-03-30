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
