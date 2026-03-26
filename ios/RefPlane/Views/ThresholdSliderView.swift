import SwiftUI

// MARK: - Threshold controls

struct ThresholdListView: View {
    @Binding var thresholds: [Double]
    let levels: Int

    var body: some View {
        let expectedHandles = max(0, levels - 1)

        VStack(spacing: 10) {
            ForEach(0..<expectedHandles, id: \.self) { index in
                LabeledSlider(
                    label: thresholdLabel(for: index),
                    value: thresholdBinding(for: index, expectedHandles: expectedHandles),
                    range: thresholdRange(for: index, expectedHandles: expectedHandles),
                    step: 0.01,
                    displayFormat: { "\(Int(($0 * 100).rounded()))%" }
                )
            }
        }
        .onAppear {
            normalizeThresholds(expectedHandles: expectedHandles)
        }
        .onChange(of: levels) { _ in
            normalizeThresholds(expectedHandles: expectedHandles)
        }
    }

    private func thresholdLabel(for index: Int) -> String {
        "Threshold \(index + 1)"
    }

    private func thresholdBinding(for index: Int, expectedHandles: Int) -> Binding<Double> {
        Binding(
            get: {
                if index < thresholds.count {
                    return thresholds[index]
                }
                return Double(index + 1) / Double(expectedHandles + 1)
            },
            set: { newValue in
                var updated = sanitizedThresholds(expectedHandles: expectedHandles)
                let lower = index > 0 ? updated[index - 1] + 0.02 : 0.02
                let upper = index < expectedHandles - 1 ? updated[index + 1] - 0.02 : 0.98
                updated[index] = max(lower, min(upper, newValue))
                thresholds = updated
            }
        )
    }

    private func thresholdRange(for index: Int, expectedHandles: Int) -> ClosedRange<Double> {
        let safeThresholds = sanitizedThresholds(expectedHandles: expectedHandles)
        let lower = index > 0 ? safeThresholds[index - 1] + 0.02 : 0.02
        let upper = index < expectedHandles - 1 ? safeThresholds[index + 1] - 0.02 : 0.98
        return lower...upper
    }

    private func normalizeThresholds(expectedHandles: Int) {
        let safe = sanitizedThresholds(expectedHandles: expectedHandles)
        if safe != thresholds {
            thresholds = safe
        }
    }

    private func sanitizedThresholds(expectedHandles: Int) -> [Double] {
        var safe = thresholds.filter { $0 >= 0 && $0 <= 1 }.sorted()
        while safe.count < expectedHandles {
            safe.append(Double(safe.count + 1) / Double(expectedHandles + 1))
        }
        safe.sort()
        if safe.count > expectedHandles {
            safe = Array(safe.prefix(expectedHandles))
        }
        return safe
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
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displayFormat(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Slider(value: $value, in: range, step: step)
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
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(label(opt)).tag(opt)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
