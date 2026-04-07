import Testing
@testable import Underpaint

// MARK: - SpectralDataStore tests

@Test
func sharedDatabaseHasPigments() {
    let db = SpectralDataStore.shared
    #expect(!db.pigments.isEmpty)
    #expect(!db.wavelengths.isEmpty)
    #expect(!db.cmfX.isEmpty)
    #expect(!db.cmfY.isEmpty)
    #expect(!db.cmfZ.isEmpty)
    #expect(!db.illuminantSpd.isEmpty)
}

@Test
func essentialPigmentsIsSubsetOfAll() {
    let essential = SpectralDataStore.essentialPigments
    let all = SpectralDataStore.shared.pigments
    #expect(!essential.isEmpty)
    #expect(essential.count <= all.count)
    for pig in essential {
        #expect(pig.essential == true)
    }
}

@Test
func essentialPigmentsAllMarkedEssential() {
    for pig in SpectralDataStore.essentialPigments {
        #expect(pig.essential)
    }
}

@Test
func essentialMastonesHaveSameCountAsEssentialPigments() {
    let masstones = SpectralDataStore.essentialMasstones
    let essentials = SpectralDataStore.essentialPigments
    #expect(masstones.count == essentials.count)
}

@Test
func essentialMastonesHaveValidOklabValues() {
    for (pigment, color) in SpectralDataStore.essentialMasstones {
        #expect(!pigment.id.isEmpty)
        #expect(color.L >= 0 && color.L <= 1.1) // slightly over 1 is possible in Oklab
        // a and b channels are typically in [-0.5, 0.5] range
        #expect(color.a > -1.0 && color.a < 1.0)
        #expect(color.b > -1.0 && color.b < 1.0)
    }
}

@Test
func pigmentByIdFindsKnownPigments() {
    // Titanium White and Carbon Black should always exist
    let white = SpectralDataStore.pigment(byId: "titanium_white")
    #expect(white != nil)
    #expect(white?.name.lowercased().contains("titanium") == true)

    let black = SpectralDataStore.pigment(byId: "carbon_black")
    #expect(black != nil)
}

@Test
func pigmentByIdReturnsNilForUnknown() {
    let result = SpectralDataStore.pigment(byId: "nonexistent_pigment_xyz")
    #expect(result == nil)
}

@Test
func globalIndicesAreAscending() {
    let subset = Array(SpectralDataStore.essentialPigments.prefix(5))
    let indices = SpectralDataStore.globalIndices(for: subset)
    #expect(indices.count == subset.count)
    for i in 0..<indices.count - 1 {
        #expect(indices[i] < indices[i + 1])
    }
}

@Test
func globalIndicesForEmptySubsetIsEmpty() {
    let indices = SpectralDataStore.globalIndices(for: [])
    #expect(indices.isEmpty)
}

@Test
func globalIndicesForAllEssentials() {
    let all = SpectralDataStore.essentialPigments
    let indices = SpectralDataStore.globalIndices(for: all)
    #expect(indices.count == all.count)
}

@Test
func pigmentDataHasReflectanceAndKOverS() {
    for pig in SpectralDataStore.essentialPigments {
        #expect(!pig.reflectance.isEmpty)
        #expect(!pig.kOverS.isEmpty)
        #expect(pig.reflectance.count == SpectralDataStore.shared.wavelengths.count)
        #expect(pig.kOverS.count == SpectralDataStore.shared.wavelengths.count)
    }
}

@Test
func databaseMetadataIsPopulated() {
    let db = SpectralDataStore.shared
    #expect(!db.description.isEmpty)
    #expect(!db.source.isEmpty)
    #expect(!db.observer.isEmpty)
    #expect(!db.illuminant.isEmpty)
}
