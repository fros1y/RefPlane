import SwiftUI

// MARK: - Multi-handle threshold slider

struct ThresholdSliderView: View {
    @Binding var thresholds: [Double]
    let levels: Int
    let colorForLevel: (Int, Int) -> Color

    var body: some View {
        GeometryReader { geo in
            let trackH: CGFloat = 20
            let handleW: CGFloat = 12
            let totalHandles = max(0, levels - 1)

            ZStack(alignment: .leading) {
                // Track background — segments colored by level
                HStack(spacing: 0) {
                    ForEach(0..<levels, id: \.self) { lvl in
                        let segStart: Double = lvl == 0             ? 0.0 : thresholds[lvl - 1]
                        let segEnd:   Double = lvl == levels - 1    ? 1.0 : thresholds[lvl]
                        let segWidth = CGFloat(segEnd - segStart) * (geo.size.width - handleW)
                        colorForLevel(lvl, levels)
                            .frame(width: max(0, segWidth), height: trackH)
                    }
                }
                .cornerRadius(4)
                .offset(x: handleW / 2)

                // Handles
                ForEach(0..<totalHandles, id: \.self) { i in
                    let val = thresholds[i]
                    let x   = CGFloat(val) * (geo.size.width - handleW)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: handleW, height: trackH + 8)
                        .shadow(radius: 2)
                        .offset(x: x)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let newVal = (drag.location.x - handleW / 2) / (geo.size.width - handleW)
                                    let lower  = i > 0             ? thresholds[i - 1] + 0.02 : 0.02
                                    let upper  = i < totalHandles - 1 ? thresholds[i + 1] - 0.02 : 0.98
                                    var t = thresholds
                                    t[i] = max(lower, min(upper, newVal))
                                    thresholds = t
                                }
                        )
                }
            }
            .frame(height: trackH + 8)
        }
        .frame(height: 28)
    }
}

// MARK: - Reusable labeled slider

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayFormat: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(displayFormat(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
            }
            Slider(value: $value, in: range, step: step)
                .tint(.blue)
        }
    }
}

// MARK: - Reusable labeled picker (segmented)

struct LabeledPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(label(opt)).tag(opt)
                }
            }
            .pickerStyle(.segmented)
            .colorMultiply(.init(white: 0.8))
        }
    }
}
