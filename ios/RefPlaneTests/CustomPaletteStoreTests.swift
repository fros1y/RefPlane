import Foundation
import Testing
@testable import Underpaint

@MainActor
private func makeStore(
    seedExamples: Bool = false,
    url: URL? = nil
) -> (store: CustomPaletteStore, url: URL) {
    let storageURL = url ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("CustomPaletteStoreTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("CustomPalettes.json")
    return (CustomPaletteStore(storageURL: storageURL, seedExamples: seedExamples), storageURL)
}

// MARK: - Round-trip persistence

@MainActor
@Test
func savedPaletteRoundTripsThroughDisk() throws {
    let (store, url) = makeStore()
    let tubes: Set<String> = ["yellow_ochre", "cad_red_medium", "titanium_white"]

    let id = try store.save(name: "Taboret", pigmentIDs: tubes)
    #expect(store.palettes.count == 1)

    // A second store instance reading the same file sees the same palette.
    let reloaded = CustomPaletteStore(storageURL: url, seedExamples: false)
    #expect(reloaded.palettes.count == 1)
    #expect(reloaded.palettes.first?.id == id)
    #expect(reloaded.palettes.first?.name == "Taboret")
    #expect(reloaded.palettes.first?.pigmentIDs == tubes)
}

@MainActor
@Test
func paletteMatchingFindsExactTubeSet() throws {
    let (store, _) = makeStore()
    let tubes: Set<String> = ["yellow_ochre", "carbon_black"]
    try store.save(name: "Mini", pigmentIDs: tubes)

    #expect(store.palette(matching: tubes)?.name == "Mini")
    #expect(store.palette(matching: ["yellow_ochre"]) == nil)
}

// MARK: - Validation

@MainActor
@Test
func duplicateNamesAreRejectedCaseAndWhitespaceInsensitively() throws {
    let (store, _) = makeStore()
    try store.save(name: "Taboret", pigmentIDs: ["yellow_ochre"])

    #expect(throws: CustomPaletteError.self) {
        try store.save(name: "  taboret ", pigmentIDs: ["carbon_black"])
    }
    #expect(store.palettes.count == 1)
}

@MainActor
@Test
func emptyNameAndEmptySelectionAreRejected() {
    let (store, _) = makeStore()

    #expect(throws: CustomPaletteError.self) {
        try store.save(name: "   ", pigmentIDs: ["yellow_ochre"])
    }
    #expect(throws: CustomPaletteError.self) {
        try store.save(name: "Empty", pigmentIDs: [])
    }
    #expect(store.palettes.isEmpty)
}

// MARK: - Rename / delete

@MainActor
@Test
func renamePersistsAndRejectsCollisions() throws {
    let (store, url) = makeStore()
    let id = try store.save(name: "Taboret", pigmentIDs: ["yellow_ochre"])
    try store.save(name: "Plein Air", pigmentIDs: ["carbon_black"])

    try store.rename(id: id, to: "Studio Wall")
    #expect(throws: CustomPaletteError.self) {
        try store.rename(id: id, to: "plein air")
    }

    let reloaded = CustomPaletteStore(storageURL: url, seedExamples: false)
    #expect(reloaded.palettes.map(\.name).contains("Studio Wall"))
}

@MainActor
@Test
func deleteRemovesPaletteFromDisk() throws {
    let (store, url) = makeStore()
    let id = try store.save(name: "Taboret", pigmentIDs: ["yellow_ochre"])
    store.delete(id: id)

    #expect(store.palettes.isEmpty)
    let reloaded = CustomPaletteStore(storageURL: url, seedExamples: false)
    #expect(reloaded.palettes.isEmpty)
}

// MARK: - Starter examples

@MainActor
@Test
func firstRunSeedsStarterPalettes() {
    let (store, url) = makeStore(seedExamples: true)

    #expect(!store.palettes.isEmpty)
    // Every seeded tube must exist in the pigment database.
    let validIDs = Set(SpectralDataStore.essentialPigments.map(\.id))
    for palette in store.palettes {
        #expect(palette.pigmentIDs.isSubset(of: validIDs))
        #expect(!palette.pigmentIDs.isEmpty)
    }

    // Seeding happens once: deleting everything must survive a reload.
    for palette in store.palettes {
        store.delete(id: palette.id)
    }
    let reloaded = CustomPaletteStore(storageURL: url, seedExamples: true)
    #expect(reloaded.palettes.isEmpty)
}

@MainActor
@Test
func starterPalettesDropUnknownPigments() {
    let starter = CustomPaletteStore.starterPalettes(validIDs: ["yellow_ochre", "titanium_white"])

    for palette in starter {
        #expect(palette.pigmentIDs.isSubset(of: ["yellow_ochre", "titanium_white"]))
    }
}

// MARK: - Corruption resilience

@MainActor
@Test
func corruptStoreFileLoadsAsEmptyWithoutCrashing() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CustomPaletteStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("CustomPalettes.json")
    try Data("not json {".utf8).write(to: url)

    let store = CustomPaletteStore(storageURL: url, seedExamples: true)
    #expect(store.palettes.isEmpty)

    // The store recovers on the next save.
    try store.save(name: "Recovered", pigmentIDs: ["yellow_ochre"])
    let reloaded = CustomPaletteStore(storageURL: url, seedExamples: false)
    #expect(reloaded.palettes.map(\.name) == ["Recovered"])
}
