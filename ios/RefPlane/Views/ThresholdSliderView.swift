import SwiftUI

// MARK: - Multi-handle threshold slider

struct ThresholdSliderView: View {
    @Binding var thresholds: [Double]
    let levels: Int
    let colorForLevel: (Int, Int) -> Color
    var onEditingEnded: (() -> Void)? = nil

    @State private var selectedHandleIndex: Int? = nil
    // Captures the threshold value at the moment each drag begins, preventing
    // cumulative drift that occurs when startValue + totalTranslation compounds
    // across re-renders mid-gesture.
    @State private var dragStartValues: [Int: Double] = [:]

    private let minimumGap: Double = 0.02
    private let trackHeight: CGFloat = 10
    private let handleDiameter: CGFloat = 34
    private let hitArea: CGFloat = 52

    var body: some View {
        let expectedHandles = max(0, levels - 1)

        GeometryReader { geo in
            let safeThresholds = sanitizedThresholds(expectedHandles: expectedHandles)
            let trackWidth = max(1, geo.size.width - hitArea)
            let centerY = geo.size.height / 2

            ZStack(alignment: .leading) {
                segmentedTrack(
                    safeThresholds: safeThresholds,
                    expectedHandles: expectedHandles,
                    trackWidth: trackWidth
                )

                ForEach(0..<expectedHandles, id: \.self) { index in
                    let value = safeThresholds[index]
                    thresholdHandle(
                        index: index,
                        value: value,
                        trackWidth: trackWidth,
                        expectedHandles: expectedHandles
                    )
                        .position(
                            x: xPosition(for: value, trackWidth: trackWidth),
                            y: centerY
                        )
                }
            }
        }
        .frame(height: hitArea)
        .onAppear {
            normalizeThresholds(expectedHandles: expectedHandles)
        }
        .onChange(of: levels) { _ in
            normalizeThresholds(expectedHandles: expectedHandles)
        }
    }

    @ViewBuilder
    private func thresholdHandle(
        index: Int,
        value: Double,
        trackWidth: CGFloat,
        expectedHandles: Int
    ) -> some View {
        let isSelected = selectedHandleIndex == index

        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color(.systemBackground))
                .frame(width: handleDiameter, height: handleDiameter)
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor : Color(.separator),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(isSelected ? 0.16 : 0.08),
                    radius: isSelected ? 6 : 3,
                    y: 2
                )

            Text("\(index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(width: hitArea, height: hitArea)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedHandleIndex = index
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    selectedHandleIndex = index
                    if dragStartValues[index] == nil {
                        dragStartValues[index] = value
                    }
                    updateThreshold(
                        at: index,
                        startValue: dragStartValues[index]!,
                        translationWidth: drag.translation.width,
                        trackWidth: trackWidth,
                        expectedHandles: expectedHandles
                    )
                }
                .onEnded { _ in
                    let startValue = dragStartValues.removeValue(forKey: index)
                    if let start = startValue, index < thresholds.count, start != thresholds[index] {
                        onEditingEnded?()
                    }
                }
        )
        .selectionFeedback(trigger: thresholds)
        .accessibilityElement()
        .accessibilityLabel("Threshold \(index + 1)")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            adjustThreshold(
                at: index,
                direction: direction,
                expectedHandles: max(0, levels - 1)
            )
        }
    }

    @ViewBuilder
    private func segmentedTrack(
        safeThresholds: [Double],
        expectedHandles: Int,
        trackWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<max(1, levels), id: \.self) { level in
                let segmentStart = level == 0 ? 0.0 : safeThresholds[level - 1]
                let segmentEnd = level == expectedHandles ? 1.0 : safeThresholds[level]
                let width = CGFloat(segmentEnd - segmentStart) * trackWidth

                colorForLevel(level, max(1, levels))
                    .opacity(0.85)
                    .frame(width: max(0, width), height: trackHeight)
            }
        }
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color(.separator), lineWidth: 1)
        }
        .padding(.horizontal, hitArea / 2)
    }

    private func xPosition(for value: Double, trackWidth: CGFloat) -> CGFloat {
        hitArea / 2 + CGFloat(value) * trackWidth
    }

    private func updateThreshold(
        at index: Int,
        startValue: Double,
        translationWidth: CGFloat,
        trackWidth: CGFloat,
        expectedHandles: Int
    ) {
        guard expectedHandles > 0 else { return }

        var updated = sanitizedThresholds(expectedHandles: expectedHandles)
        let proposedValue = startValue + Double(translationWidth / trackWidth)
        let lowerBound = index > 0 ? updated[index - 1] + minimumGap : minimumGap
        let upperBound = index < expectedHandles - 1 ? updated[index + 1] - minimumGap : 1 - minimumGap

        updated[index] = max(lowerBound, min(upperBound, proposedValue))
        thresholds = updated
    }

    private func adjustThreshold(
        at index: Int,
        direction: AccessibilityAdjustmentDirection,
        expectedHandles: Int
    ) {
        guard expectedHandles > 0 else { return }

        let delta: Double
        switch direction {
        case .increment:
            delta = 0.01
        case .decrement:
            delta = -0.01
        @unknown default:
            return
        }

        var updated = sanitizedThresholds(expectedHandles: expectedHandles)
        let lowerBound = index > 0 ? updated[index - 1] + minimumGap : minimumGap
        let upperBound = index < expectedHandles - 1 ? updated[index + 1] - minimumGap : 1 - minimumGap

        updated[index] = max(lowerBound, min(upperBound, updated[index] + delta))
        thresholds = updated
        onEditingEnded?()
    }

    private func normalizeThresholds(expectedHandles: Int) {
        let safe = sanitizedThresholds(expectedHandles: expectedHandles)
        if safe != thresholds {
            thresholds = safe
        }
        if let selectedHandleIndex, selectedHandleIndex >= expectedHandles {
            self.selectedHandleIndex = nil
        }
    }

    private func sanitizedThresholds(expectedHandles: Int) -> [Double] {
        ThresholdUtilities.sanitized(thresholds, levels: expectedHandles + 1)
    }
}

private extension View {
    @ViewBuilder
    func selectionFeedback<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.selection, trigger: trigger)
        } else {
            self
        }
    }
}

// MARK: - Reusable labeled slider

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let displayFormat: (Double) -> String
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var valueAtDragStart: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(displayFormat(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            TouchEventSlider(
                label: label,
                value: $value,
                range: range,
                step: step,
                onEditingChanged: { editing in
                    if editing {
                        valueAtDragStart = value
                    }
                    onEditingChanged?(editing)
                    if !editing {
                        valueAtDragStart = nil
                    }
                }
            )
        }
    }
}

private struct TouchEventSlider: UIViewRepresentable {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onEditingChanged: ((Bool) -> Void)?

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(snappedValue(value))
        slider.isContinuous = true

        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchDown(_:)),
            for: .touchDown
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchDragInside(_:)),
            for: .touchDragInside
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchDragOutside(_:)),
            for: .touchDragOutside
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchUpInside(_:)),
            for: .touchUpInside
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchUpOutside(_:)),
            for: .touchUpOutside
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchCancel(_:)),
            for: .touchCancel
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )

        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        context.coordinator.parent = self
        uiView.minimumValue = Float(range.lowerBound)
        uiView.maximumValue = Float(range.upperBound)

        let snapped = Float(snappedValue(value))
        if !uiView.isTracking, abs(uiView.value - snapped) > 0.000_001 {
            uiView.setValue(snapped, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func snappedValue(_ rawValue: Double) -> Double {
        guard step > 0 else {
            return min(range.upperBound, max(range.lowerBound, rawValue))
        }

        let bounded = min(range.upperBound, max(range.lowerBound, rawValue))
        let steps = ((bounded - range.lowerBound) / step).rounded()
        let snapped = range.lowerBound + steps * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    final class Coordinator: NSObject {
        var parent: TouchEventSlider
        private var isEditing = false

        init(parent: TouchEventSlider) {
            self.parent = parent
        }

        @objc func touchDown(_ sender: UISlider) {
            setEditing(true)
        }

        @objc func touchDragInside(_ sender: UISlider) {}

        @objc func touchDragOutside(_ sender: UISlider) {}

        @objc func touchUpInside(_ sender: UISlider) {
            setEditing(false)
        }

        @objc func touchUpOutside(_ sender: UISlider) {
            setEditing(false)
        }

        @objc func touchCancel(_ sender: UISlider) {
            setEditing(false)
        }

        @objc func valueChanged(_ sender: UISlider) {
            let snapped = parent.snappedValue(Double(sender.value))
            if abs(Double(sender.value) - snapped) > 0.000_001 {
                sender.setValue(Float(snapped), animated: false)
            }
            parent.value = snapped

            if !sender.isTracking {
                setEditing(false)
            }
        }

        private func setEditing(_ editing: Bool) {
            guard editing != isEditing else { return }

            isEditing = editing
            parent.onEditingChanged?(editing)
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
                .foregroundStyle(.primary)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { opt in
                    Text(label(opt)).tag(opt)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
