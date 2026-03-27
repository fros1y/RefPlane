import Testing
@testable import Underpaint

@Test
func paletteSectionsPreserveBandMembershipAndIndexOrder() {
    for seed in 1...200 {
        var generator = SeededGenerator(seed: UInt64(seed))
        let paletteBands = generator.intArray(count: 0...30, values: -2...5)
        let sections = PaletteSections.makeSections(paletteBands: paletteBands)
        let flattenedIndices = sections.flatMap(\.indices)
        let expectedIndices = paletteBands.enumerated().compactMap { index, band in
            band >= 0 ? index : nil
        }

        #expect(flattenedIndices.sorted() == expectedIndices.sorted())
        #expect(sections.map(\.band) == sections.map(\.band).sorted())

        for section in sections {
            #expect(section.indices == section.indices.sorted())
            #expect(section.indices.allSatisfy { paletteBands[$0] == section.band })
        }
    }
}

@Test
func paletteSectionsExcludeNegativeBands() {
    let sections = PaletteSections.makeSections(paletteBands: [-1, 0, 2, -1, 2])

    #expect(sections == [
        PaletteBandSection(band: 0, indices: [1]),
        PaletteBandSection(band: 2, indices: [2, 4]),
    ])
}
