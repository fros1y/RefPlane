import Foundation

// MARK: - Spectral database loader with caching

enum SpectralDataStore {

    /// Lazily loaded and cached spectral database.
    static let shared: SpectralDatabase = {
        guard let url = Bundle.main.url(forResource: "GoldenAcrylicsKS", withExtension: "json") else {
            fatalError("GoldenAcrylicsKS.json not found in app bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SpectralDatabase.self, from: data)
        } catch {
            fatalError("Failed to decode GoldenAcrylicsKS.json: \(error)")
        }
    }()

    /// Essential pigments only (curated ~20 set).
    static let essentialPigments: [PigmentData] = {
        shared.pigments.filter { $0.essential }
    }()

    /// Pre-computed Oklab masstone color for each essential pigment.
    static let essentialMasstones: [(pigment: PigmentData, color: OklabColor)] = {
        essentialPigments.map { pigment in
            let color = KubelkaMunkMixer.pigmentToOklab(
                kOverS: pigment.kOverS,
                database: shared
            )
            return (pigment: pigment, color: color)
        }
    }()

    /// Lookup essential pigment by ID.
    static func pigment(byId id: String) -> PigmentData? {
        shared.pigments.first { $0.id == id }
    }
}
