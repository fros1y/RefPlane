import Foundation
import Testing
@testable import Underpaint

// MARK: - PigmentLookupTable loading errors

@Test
func loadingFromNonexistentFileThrows() {
    let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent_pigment_lookup.bin")
    #expect(throws: (any Error).self) {
        _ = try PigmentLookupTable(url: bogusURL)
    }
}

@Test
func loadingTooSmallDataThrowsTooSmall() {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tiny.bin")
    let tinyData = Data(repeating: 0, count: 10)
    try! tinyData.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    do {
        _ = try PigmentLookupTable(url: tempURL)
        Issue.record("Expected tooSmall error")
    } catch let error as PigmentLookupTable.LoadError {
        #expect(error == .tooSmall)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test
func loadingBadMagicThrowsBadMagic() {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("badmagic.bin")
    var data = Data(repeating: 0, count: 100)
    // Write bad magic bytes (not "KMLT")
    data[0] = 0x00
    data[1] = 0x00
    data[2] = 0x00
    data[3] = 0x00
    try! data.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    do {
        _ = try PigmentLookupTable(url: tempURL)
        Issue.record("Expected badMagic error")
    } catch let error as PigmentLookupTable.LoadError {
        #expect(error == .badMagic)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test
func loadingTruncatedDataThrows() {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("truncated.bin")
    var data = Data(repeating: 0, count: 30)
    // Write correct magic "KMLT"
    data[0] = 0x4B // K
    data[1] = 0x4D // M
    data[2] = 0x4C // L
    data[3] = 0x54 // T
    // pigmentCount (byte 5) = 2
    data[5] = 2
    // resolution (bytes 6-7) = 8
    data[6] = 8; data[7] = 0
    // pairCount (bytes 8-11) = 100 (way more than data supports)
    data[8] = 100; data[9] = 0; data[10] = 0; data[11] = 0
    // tripletCount = 0
    // pairSteps = 1
    data[16] = 1; data[17] = 0; data[18] = 0; data[19] = 0
    try! data.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    do {
        _ = try PigmentLookupTable(url: tempURL)
        Issue.record("Expected truncated error")
    } catch let error as PigmentLookupTable.LoadError {
        #expect(error == .truncated)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

// MARK: - Synthetic valid table

/// Build a minimal valid PigmentLookup.bin with 2 pigments, 1 pair, 0 triplets, 1 step.
private func makeSyntheticLookupURL(filename: String = UUID().uuidString) throws -> URL {
    let N = 2          // pigmentCount
    let pairCount = 1  // C(2,2) = 1
    let tripletCount = 0
    let pairSteps = 1
    let tripletSteps = 0
    let totalEntries = pairCount * pairSteps + tripletCount * tripletSteps

    var data = Data(count: 24 + totalEntries * 10)

    // Header
    data[0] = 0x4B; data[1] = 0x4D; data[2] = 0x4C; data[3] = 0x54 // KMLT
    data[5] = UInt8(N)
    data[6] = 8; data[7] = 0 // resolution = 8

    func writeLE32(_ value: Int, offset: Int) {
        data[offset] = UInt8(value & 0xFF)
        data[offset+1] = UInt8((value >> 8) & 0xFF)
        data[offset+2] = UInt8((value >> 16) & 0xFF)
        data[offset+3] = UInt8((value >> 24) & 0xFF)
    }
    writeLE32(pairCount, offset: 8)
    writeLE32(tripletCount, offset: 12)
    writeLE32(pairSteps, offset: 16)
    writeLE32(tripletSteps, offset: 20)

    // Single entry at offset 24: pigments 0,1 with a0=4,a1=4 (packed=0x44=68)
    let entryOffset = 24
    data[entryOffset] = 0     // i0
    data[entryOffset+1] = 1   // i1
    data[entryOffset+2] = 0   // i2 (pair, so 0)
    data[entryOffset+3] = 68  // packed: a0=4, a1=4

    // L=0.5 as Float16
    let halfBits = Float16(0.5).bitPattern
    data[entryOffset+4] = UInt8(halfBits & 0xFF)
    data[entryOffset+5] = UInt8(halfBits >> 8)
    // a=0.0 as Float16
    let zeroBits = Float16(0.0).bitPattern
    data[entryOffset+6] = UInt8(zeroBits & 0xFF)
    data[entryOffset+7] = UInt8(zeroBits >> 8)
    // b=0.0 as Float16
    data[entryOffset+8] = UInt8(zeroBits & 0xFF)
    data[entryOffset+9] = UInt8(zeroBits >> 8)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename)_lookup.bin")
    try data.write(to: url)
    return url
}

@Test
func syntheticTableLoadsCorrectly() throws {
    let url = try makeSyntheticLookupURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let table = try PigmentLookupTable(url: url)
    #expect(table.pigmentCount == 2)
    #expect(table.pairCount == 1)
    #expect(table.tripletCount == 0)
    #expect(table.pairSteps == 1)
    #expect(table.tripletSteps == 0)
}

@Test
func syntheticTableReadEntry() throws {
    let url = try makeSyntheticLookupURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let table = try PigmentLookupTable(url: url)
    let entry = table.readEntry(at: 0)
    #expect(entry.i0 == 0)
    #expect(entry.i1 == 1)
    #expect(entry.i2 == 0)
    #expect(entry.a0 == 4)
    #expect(entry.a1 == 4)
    #expect(abs(entry.color.L - 0.5) < 0.01)
}

@Test
func syntheticTableFindBestReturnsMatch() throws {
    let url = try makeSyntheticLookupURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let table = try PigmentLookupTable(url: url)
    let target = OklabColor(L: 0.5, a: 0.0, b: 0.0)
    let result = table.findBest(
        for: target,
        enabledGlobalIndices: [0, 1],
        maxPigments: 2
    )
    #expect(result != nil)
    #expect(result!.distSq < 0.01)
}

@Test
func findBestWithNoEnabledIndicesReturnsNil() throws {
    let url = try makeSyntheticLookupURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let table = try PigmentLookupTable(url: url)
    let result = table.findBest(
        for: OklabColor(L: 0.5, a: 0, b: 0),
        enabledGlobalIndices: [],
        maxPigments: 2
    )
    #expect(result == nil)
}

@Test
func syntheticTableMasstones() throws {
    let url = try makeSyntheticLookupURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let table = try PigmentLookupTable(url: url)
    let masstones = table.masstones
    #expect(masstones.count == 2)
}
