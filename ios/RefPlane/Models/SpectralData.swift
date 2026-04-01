import Foundation
import SwiftUI

// MARK: - Spectral database models (Codable, loaded from GoldenAcrylicsKS.json)

struct SpectralDatabase: Codable {
    let description: String
    let source: String
    let observer: String
    let illuminant: String
    let wavelengths: [Int]
    let cmfX: [Float]
    let cmfY: [Float]
    let cmfZ: [Float]
    let illuminantSpd: [Float]
    let pigments: [PigmentData]
}

struct PigmentCIELab: Codable {
    let L: Float
    let a: Float
    let b: Float
}

struct PigmentData: Codable, Identifiable {
    let id: String
    let name: String
    let productNumber: Int
    let essential: Bool
    let cielab: PigmentCIELab
    let reflectance: [Float]
    let kOverS: [Float]
}

// MARK: - Pigment recipe (output of decomposition)

struct RecipeComponent: Identifiable {
    let pigmentId: String
    let pigmentName: String
    let concentration: Float

    var id: String { pigmentId }
}

struct PigmentRecipe {
    let components: [RecipeComponent]
    let predictedColor: OklabColor
    let deltaE: Float
}

struct DecompositionResult {
    let recipes: [PigmentRecipe]
    /// Union of all pigment IDs used across all recipes.
    let globalPalette: [String]
}
