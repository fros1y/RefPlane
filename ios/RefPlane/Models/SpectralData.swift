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

extension PigmentRecipe {
    /// The pigment carrying the highest concentration in this mix.
    var dominantPigmentID: String? {
        components.max(by: { $0.concentration < $1.concentration })?.pigmentId
    }

    /// Mixing ratio reduced to small whole-number parts (e.g. 3 : 1),
    /// keyed by pigment ID — the form painters actually measure by.
    var simplifiedParts: [String: Int] {
        let rawParts = components.map { component in
            (pigmentId: component.pigmentId, parts: max(1, Int((component.concentration * 8).rounded())))
        }
        let divisor = rawParts
            .map(\.parts)
            .reduce(0) { current, parts in
                current == 0 ? parts : Self.greatestCommonDivisor(current, parts)
            }

        return rawParts.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.pigmentId] = entry.parts / max(1, divisor)
        }
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
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

struct DecompositionResult {
    let recipes: [PigmentRecipe]
    /// Union of all pigment IDs used across all recipes.
    let globalPalette: [String]
}
