import Testing
@testable import Underpaint

// MARK: - SpectralData model tests

@Test
func pigmentCIELabStoresValues() {
    let lab = PigmentCIELab(L: 50.0, a: -10.5, b: 25.3)
    #expect(lab.L == 50.0)
    #expect(lab.a == -10.5)
    #expect(lab.b == 25.3)
}

@Test
func pigmentDataIdentifiableUsesId() {
    let pigment = PigmentData(
        id: "test_pigment",
        name: "Test Pigment",
        productNumber: 42,
        essential: true,
        cielab: PigmentCIELab(L: 50, a: 0, b: 0),
        reflectance: [0.5, 0.6],
        kOverS: [0.1, 0.2]
    )
    #expect(pigment.id == "test_pigment")
    #expect(pigment.name == "Test Pigment")
    #expect(pigment.productNumber == 42)
    #expect(pigment.essential == true)
}

@Test
func pigmentDataNonEssentialFlag() {
    let pigment = PigmentData(
        id: "optional_pigment",
        name: "Optional",
        productNumber: 99,
        essential: false,
        cielab: PigmentCIELab(L: 70, a: 5, b: -3),
        reflectance: [],
        kOverS: []
    )
    #expect(pigment.essential == false)
}

@Test
func recipeComponentIdentifiableUsesPigmentId() {
    let component = RecipeComponent(
        pigmentId: "titanium_white",
        pigmentName: "Titanium White",
        concentration: 0.75
    )
    #expect(component.id == "titanium_white")
    #expect(component.pigmentName == "Titanium White")
    #expect(component.concentration == 0.75)
}

@Test
func pigmentRecipeStoresComponentsAndPredictedColor() {
    let components = [
        RecipeComponent(pigmentId: "a", pigmentName: "A", concentration: 0.6),
        RecipeComponent(pigmentId: "b", pigmentName: "B", concentration: 0.4),
    ]
    let recipe = PigmentRecipe(
        components: components,
        predictedColor: OklabColor(L: 0.7, a: 0.01, b: -0.02),
        deltaE: 1.5
    )
    #expect(recipe.components.count == 2)
    #expect(recipe.deltaE == 1.5)
    #expect(abs(recipe.predictedColor.L - 0.7) < 1e-6)
}

@Test
func decompositionResultStoresGlobalPalette() {
    let result = DecompositionResult(
        recipes: [],
        globalPalette: ["titanium_white", "carbon_black"]
    )
    #expect(result.recipes.isEmpty)
    #expect(result.globalPalette.count == 2)
    #expect(result.globalPalette.contains("titanium_white"))
}

// MARK: - KMLookupEntry computed properties

@Test
func lookupEntryA0A1A2FromPacked() {
    // packed = (a0 << 4) | a1; a2 = 8 - a0 - a1
    // a0=5, a1=2 → packed = 0x52 = 82, a2 = 1
    let entry = KMLookupEntry(
        i0: 0, i1: 1, i2: 2, packed: 82,
        L_bits: 0, a_bits: 0, b_bits: 0
    )
    #expect(entry.a0 == 5)
    #expect(entry.a1 == 2)
    #expect(entry.a2 == 1)
    #expect(entry.a0 + entry.a1 + entry.a2 == 8)
}

@Test
func lookupEntryPackedZeroMeansAllA2() {
    // packed=0 → a0=0, a1=0, a2=8
    let entry = KMLookupEntry(
        i0: 0, i1: 0, i2: 0, packed: 0,
        L_bits: 0, a_bits: 0, b_bits: 0
    )
    #expect(entry.a0 == 0)
    #expect(entry.a1 == 0)
    #expect(entry.a2 == 8)
}

@Test
func lookupEntryPaintCountPair() {
    // Pair mode: only a0 and a1 matter
    // a0=4, a1=4 → packed = 0x44 = 68
    let entry = KMLookupEntry(
        i0: 0, i1: 1, i2: 0, packed: 68,
        L_bits: 0, a_bits: 0, b_bits: 0
    )
    #expect(entry.paintCount(isTriplet: false) == 2)

    // a0=8, a1=0 → packed = 0x80 = 128 → single paint
    let single = KMLookupEntry(
        i0: 0, i1: 1, i2: 0, packed: 128,
        L_bits: 0, a_bits: 0, b_bits: 0
    )
    #expect(single.paintCount(isTriplet: false) == 1)
}

@Test
func lookupEntryPaintCountTriplet() {
    // a0=3, a1=3, a2=2 → packed = 0x33 = 51
    let entry = KMLookupEntry(
        i0: 0, i1: 1, i2: 2, packed: 51,
        L_bits: 0, a_bits: 0, b_bits: 0
    )
    #expect(entry.paintCount(isTriplet: true) == 3)

    // a0=4, a1=4, a2=0 → packed = 0x44 = 68 → two paints
    let two = KMLookupEntry(
        i0: 0, i1: 1, i2: 2, packed: 68,
        L_bits: 0, a_bits: 0, b_bits: 0
    )
    #expect(two.paintCount(isTriplet: true) == 2)
}

@Test
func lookupEntryColorDecodesFloat16Bits() {
    // Float16(1.0).bitPattern = 0x3C00
    let oneBits: UInt16 = Float16(1.0).bitPattern
    let entry = KMLookupEntry(
        i0: 0, i1: 0, i2: 0, packed: 0,
        L_bits: oneBits, a_bits: 0, b_bits: 0
    )
    let color = entry.color
    #expect(abs(color.L - 1.0) < 1e-3)
    #expect(abs(color.a) < 1e-3)
    #expect(abs(color.b) < 1e-3)
}

// MARK: - ProcessingResult.empty

@Test
func processingResultEmptyHasEmptyCollections() {
    let empty = ProcessingResult.empty
    #expect(empty.palette.isEmpty)
    #expect(empty.paletteBands.isEmpty)
    #expect(empty.pixelBands.isEmpty)
    #expect(empty.pigmentRecipes == nil)
    #expect(empty.selectedTubes.isEmpty)
    #expect(empty.clippedRecipeIndices.isEmpty)
}
