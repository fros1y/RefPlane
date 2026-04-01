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

    /// Pre-computed KM lookup table for all 78 pigments.
    /// Loaded lazily from PigmentLookup.bin in the app bundle.
    /// Returns nil if the binary asset is absent (falls back to runtime computation).
    static let sharedLookupTable: PigmentLookupTable? = {
        guard let url = Bundle.main.url(forResource: "PigmentLookup", withExtension: "bin") else {
            print("[SpectralDataStore] PigmentLookup.bin not found – falling back to runtime table build")
            return nil
        }
        do {
            let table = try PigmentLookupTable(url: url)
            print("[SpectralDataStore] Loaded PigmentLookup.bin: \(table.pairCount) pairs, \(table.tripletCount) triplets")
            return table
        } catch {
            print("[SpectralDataStore] Failed to load PigmentLookup.bin: \(error)")
            return nil
        }
    }()

    /// Map every pigment in `subset` to its global index in `shared.pigments`.
    /// Returns indices in ascending order.
    static func globalIndices(for subset: [PigmentData]) -> [Int] {
        let all = shared.pigments
        return subset.compactMap { pig in
            all.firstIndex(where: { $0.id == pig.id })
        }.sorted()
    }
}
