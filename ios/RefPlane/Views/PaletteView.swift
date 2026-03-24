import SwiftUI

struct PaletteView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let maxBand = (state.paletteBands.max() ?? -1)
            if maxBand >= 0 {
                ForEach(0...maxBand, id: \.self) { band in
                    let indices = state.paletteBands.enumerated()
                        .filter { $0.element == band }
                        .map { $0.offset }
                    if !indices.isEmpty {
                        HStack(spacing: 4) {
                            Text("Band \(band + 1)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 42, alignment: .leading)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(indices, id: \.self) { idx in
                                        let color = state.paletteColors[idx]
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(color)
                                            .frame(width: 32, height: 24)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(
                                                        state.isolatedBand == band
                                                            ? Color.white : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if state.isolatedBand == band {
                                state.isolatedBand = nil
                            } else {
                                state.isolatedBand = band
                            }
                        }
                    }
                }
            }
        }
    }
}
