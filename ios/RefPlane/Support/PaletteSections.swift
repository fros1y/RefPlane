import Foundation

struct PaletteBandSection: Equatable, Sendable {
    let band: Int
    let indices: [Int]
}

enum PaletteSections {
    static func makeSections(paletteBands: [Int], paletteCount: Int? = nil) -> [PaletteBandSection] {
        let upperBound = min(paletteBands.count, paletteCount ?? paletteBands.count)
        var grouped: [Int: [Int]] = [:]

        for index in 0..<upperBound {
            let band = paletteBands[index]
            guard band >= 0 else { continue }
            grouped[band, default: []].append(index)
        }

        return grouped.keys.sorted().map { band in
            PaletteBandSection(band: band, indices: grouped[band] ?? [])
        }
    }
}
