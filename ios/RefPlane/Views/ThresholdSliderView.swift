import SwiftUI

// MARK: - Multi-handle threshold slider

struct ThresholdSliderView: View {
    @Binding var thresholds: [Double]
    let levels: Int
    let colorForLevel: (Int, Int) -> Color
    var onEditingEnded: (() -> Void)? = nil

    var body: some View {
        let expectedHandles = max(0, levels - 1)

        MultiHandleSliderRepresentable(
            thresholds: $thresholds,
            expectedHandles: expectedHandles,
            minimumGap: 0.02,
            colorForLevel: { level in
                colorForLevel(level, max(1, levels))
            },
            onEditingEnded: onEditingEnded
        )
        .frame(height: 52)
    }
}

// MARK: - UIKit multi-handle slider

private struct MultiHandleSliderRepresentable: UIViewRepresentable {
    @Binding var thresholds: [Double]
    let expectedHandles: Int
    let minimumGap: Double
    let colorForLevel: (Int) -> Color
    let onEditingEnded: (() -> Void)?

    func makeUIView(context: Context) -> MultiHandleSliderControl {
        let control = MultiHandleSliderControl()
        control.minimumGap = minimumGap
        control.onThresholdsChanged = { newValues in
            thresholds = newValues
        }
        control.onEditingEnded = onEditingEnded
        updateControl(control)
        return control
    }

    func updateUIView(_ uiView: MultiHandleSliderControl, context: Context) {
        updateControl(uiView)
    }

    private func updateControl(_ control: MultiHandleSliderControl) {
        let safe = ThresholdUtilities.sanitized(thresholds, levels: expectedHandles + 1)
        control.expectedHandles = expectedHandles

        // Build UIColors for each segment
        var segmentColors: [UIColor] = []
        for level in 0...max(0, expectedHandles) {
            let swiftColor = colorForLevel(level)
            segmentColors.append(UIColor(swiftColor))
        }
        control.segmentColors = segmentColors

        // Only update values when not tracking to avoid fighting the user
        if !control.isActivelyDragging {
            control.setThresholds(safe)
        }
    }
}

// MARK: - Custom UIControl

private final class MultiHandleSliderControl: UIControl {
    var minimumGap: Double = 0.02
    var onThresholdsChanged: (([Double]) -> Void)?
    var onEditingEnded: (() -> Void)?
    var expectedHandles: Int = 0

    var segmentColors: [UIColor] = [] {
        didSet { setNeedsDisplay() }
    }

    private(set) var isActivelyDragging = false

    private var thresholdValues: [Double] = []
    private var activeHandleIndex: Int? = nil
    private var dragStartValue: Double = 0

    private let trackHeight: CGFloat = 10
    private let handleDiameter: CGFloat = 30
    private let trackInset: CGFloat = 26  // half of hitArea

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setThresholds(_ values: [Double]) {
        thresholdValues = values
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let trackWidth = max(1, bounds.width - trackInset * 2)
        let trackY = (bounds.height - trackHeight) / 2

        // Draw segmented track
        let trackRect = CGRect(x: trackInset, y: trackY, width: trackWidth, height: trackHeight)
        let trackPath = UIBezierPath(roundedRect: trackRect, cornerRadius: trackHeight / 2)
        ctx.saveGState()
        trackPath.addClip()

        let count = max(1, expectedHandles + 1)
        for level in 0..<count {
            let segStart = level == 0 ? 0.0 : (level - 1 < thresholdValues.count ? thresholdValues[level - 1] : 1.0)
            let segEnd = level < thresholdValues.count ? thresholdValues[level] : 1.0
            let x0 = trackInset + CGFloat(segStart) * trackWidth
            let x1 = trackInset + CGFloat(segEnd) * trackWidth
            let color = level < segmentColors.count ? segmentColors[level] : UIColor.systemGray3
            ctx.setFillColor(color.withAlphaComponent(0.85).cgColor)
            ctx.fill(CGRect(x: x0, y: trackY, width: max(0, x1 - x0), height: trackHeight))
        }

        ctx.restoreGState()

        // Track border
        UIColor.separator.setStroke()
        trackPath.lineWidth = 1
        trackPath.stroke()

        // Draw handles
        let centerY = bounds.height / 2
        for (i, value) in thresholdValues.enumerated() {
            let x = trackInset + CGFloat(value) * trackWidth
            let isActive = activeHandleIndex == i
            drawHandle(in: ctx, at: CGPoint(x: x, y: centerY), index: i, isActive: isActive)
        }
    }

    private func drawHandle(in ctx: CGContext, at center: CGPoint, index: Int, isActive: Bool) {
        let radius = handleDiameter / 2
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: handleDiameter, height: handleDiameter)

        // Shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: 2),
            blur: isActive ? 6 : 3,
            color: UIColor.black.withAlphaComponent(isActive ? 0.16 : 0.08).cgColor
        )
        let circlePath = UIBezierPath(ovalIn: rect)
        if isActive {
            ctx.setFillColor((tintColor ?? .systemBlue).cgColor)
        } else {
            ctx.setFillColor(UIColor.systemBackground.cgColor)
        }
        circlePath.fill()
        ctx.restoreGState()

        // Stroke
        let strokeColor: UIColor = isActive ? (tintColor ?? .systemBlue) : .separator
        strokeColor.setStroke()
        circlePath.lineWidth = isActive ? 2.5 : 1
        circlePath.stroke()

        // Label
        let label = "\(index + 1)" as NSString
        let labelFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let textColor = isActive ? UIColor.white : UIColor.label
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: textColor]
        let textSize = label.size(withAttributes: attrs)
        let textOrigin = CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
        label.draw(at: textOrigin, withAttributes: attrs)
    }

    // MARK: - Touch handling

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        let trackWidth = max(1, bounds.width - trackInset * 2)

        // Find the closest handle within a generous hit radius
        let hitRadius: CGFloat = 30
        var bestIndex: Int? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude

        let centerY = bounds.height / 2

        for (i, value) in thresholdValues.enumerated() {
            let handleX = trackInset + CGFloat(value) * trackWidth
            let handleCenter = CGPoint(x: handleX, y: centerY)
            let dist = hypot(location.x - handleCenter.x, location.y - handleCenter.y)
            if dist < hitRadius && dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }

        guard let index = bestIndex else { return false }

        activeHandleIndex = index
        dragStartValue = thresholdValues[index]
        isActivelyDragging = true
        setNeedsDisplay()

        // Haptic feedback
        let feedback = UISelectionFeedbackGenerator()
        feedback.selectionChanged()

        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard let index = activeHandleIndex else { return false }
        let location = touch.location(in: self)
        let trackWidth = max(1, bounds.width - trackInset * 2)

        let rawValue = Double((location.x - trackInset) / trackWidth)
        let lowerBound = index > 0 ? thresholdValues[index - 1] + minimumGap : minimumGap
        let upperBound = index < thresholdValues.count - 1 ? thresholdValues[index + 1] - minimumGap : 1 - minimumGap
        let clamped = max(lowerBound, min(upperBound, rawValue))

        thresholdValues[index] = clamped
        onThresholdsChanged?(thresholdValues)
        setNeedsDisplay()

        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        finishDrag()
    }

    override func cancelTracking(with event: UIEvent?) {
        finishDrag()
    }

    private func finishDrag() {
        let didMove = activeHandleIndex != nil &&
            activeHandleIndex! < thresholdValues.count &&
            thresholdValues[activeHandleIndex!] != dragStartValue

        isActivelyDragging = false
        activeHandleIndex = nil
        setNeedsDisplay()

        if didMove {
            onEditingEnded?()
        }
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
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
