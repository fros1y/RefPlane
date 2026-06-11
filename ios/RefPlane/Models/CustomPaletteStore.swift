import Foundation
import Observation

// MARK: - Model

/// A named subset of pigment tubes — "the 12 tubes actually on my taboret".
struct CustomPalette: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var pigmentIDs: Set<String>
    var createdAt: Date
    var updatedAt: Date
}

enum CustomPaletteError: LocalizedError {
    case emptyName
    case duplicateName
    case emptySelection
    case paletteNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Palette name cannot be empty."
        case .duplicateName:
            return "A palette with that name already exists."
        case .emptySelection:
            return "Select at least one pigment before saving a palette."
        case .paletteNotFound:
            return "Palette not found."
        }
    }
}

// MARK: - Store

/// Persists named custom palettes as a flat JSON file in Application Support.
@Observable
@MainActor
final class CustomPaletteStore {
    static let shared = CustomPaletteStore()

    private struct StoreFile: Codable {
        var schemaVersion: Int
        var palettes: [CustomPalette]
    }

    private(set) var palettes: [CustomPalette] = []

    @ObservationIgnored private let storageURL: URL

    /// - Parameter storageURL: Override for tests; defaults to
    ///   `Application Support/CustomPalettes.json`.
    /// - Parameter seedExamples: Seed the starter palettes when no store
    ///   file exists yet (first run).
    init(storageURL: URL? = nil, seedExamples: Bool = true) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load(seedExamplesIfEmpty: seedExamples)
    }

    // MARK: Queries

    /// The saved palette whose tubes exactly match the given selection.
    func palette(matching pigmentIDs: Set<String>) -> CustomPalette? {
        palettes.first { $0.pigmentIDs == pigmentIDs }
    }

    // MARK: Mutations

    @discardableResult
    func save(name rawName: String, pigmentIDs: Set<String>) throws -> UUID {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw CustomPaletteError.emptyName
        }
        guard !pigmentIDs.isEmpty else {
            throw CustomPaletteError.emptySelection
        }
        let normalized = Self.normalizedName(name)
        guard !palettes.contains(where: { Self.normalizedName($0.name) == normalized }) else {
            throw CustomPaletteError.duplicateName
        }

        let now = Date()
        let palette = CustomPalette(
            id: UUID(),
            name: name,
            pigmentIDs: pigmentIDs,
            createdAt: now,
            updatedAt: now
        )
        palettes.append(palette)
        sortAndPersist()
        return palette.id
    }

    func rename(id: UUID, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw CustomPaletteError.emptyName
        }
        let normalized = Self.normalizedName(name)
        guard !palettes.contains(where: { $0.id != id && Self.normalizedName($0.name) == normalized }) else {
            throw CustomPaletteError.duplicateName
        }
        guard let index = palettes.firstIndex(where: { $0.id == id }) else {
            throw CustomPaletteError.paletteNotFound
        }

        palettes[index].name = name
        palettes[index].updatedAt = Date()
        sortAndPersist()
    }

    func delete(id: UUID) {
        palettes.removeAll { $0.id == id }
        persist()
    }

    // MARK: Persistence

    private func load(seedExamplesIfEmpty: Bool) {
        guard let data = try? Data(contentsOf: storageURL) else {
            if seedExamplesIfEmpty {
                palettes = Self.starterPalettes(
                    validIDs: Set(SpectralDataStore.essentialPigments.map(\.id))
                )
                persist()
            }
            return
        }

        do {
            let file = try JSONDecoder().decode(StoreFile.self, from: data)
            if file.schemaVersion == 1 {
                palettes = file.palettes.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        } catch {
            // A corrupt store should not take the feature down; start fresh
            // without clobbering the file until the next successful save.
            palettes = []
        }
    }

    private func sortAndPersist() {
        palettes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(StoreFile(schemaVersion: 1, palettes: palettes))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            assertionFailure("Failed to persist custom palettes: \(error)")
        }
    }

    private static func defaultStorageURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support.appendingPathComponent("CustomPalettes.json")
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Curated starter palettes that demo the feature on first run.
    /// IDs are validated against the pigment database; anything stale is dropped.
    static func starterPalettes(validIDs: Set<String>, now: Date = Date()) -> [CustomPalette] {
        let curated: [(name: String, ids: Set<String>)] = [
            ("Studio (12)", [
                "cad_red_medium", "quin_crimson", "cadmium_orange",
                "cad_yellow_medium", "yellow_ochre", "burnt_sienna",
                "burnt_umber", "ultramarine_blue", "phthalo_blue_gs",
                "phthalo_green_bs", "titanium_white", "carbon_black",
            ]),
            ("Plein Air (6)", [
                "cad_red_medium", "cad_yellow_medium", "ultramarine_blue",
                "yellow_ochre", "burnt_sienna", "titanium_white",
            ]),
            ("Earth Tones (8)", [
                "yellow_ochre", "raw_sienna", "burnt_sienna", "raw_umber",
                "burnt_umber", "paynes_gray", "titanium_white", "carbon_black",
            ]),
        ]

        return curated.compactMap { entry in
            let ids = entry.ids.intersection(validIDs)
            guard !ids.isEmpty else { return nil }
            return CustomPalette(
                id: UUID(),
                name: entry.name,
                pigmentIDs: ids,
                createdAt: now,
                updatedAt: now
            )
        }
    }
}
