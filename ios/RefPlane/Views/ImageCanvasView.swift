import SwiftUI

enum CanvasBandTapAction: Equatable {
    case inspect(Int?)
    case focus(Int)
    case resetViewport
}

struct CanvasBandTapTracker {
    struct Entry: Equatable {
        let band: Int?
        let timestamp: TimeInterval
    }

    static let defaultRepeatWindow: TimeInterval = 0.45

    let repeatWindow: TimeInterval
    private(set) var lastTap: Entry?

    init(
        repeatWindow: TimeInterval = Self.defaultRepeatWindow,
        lastTap: Entry? = nil
    ) {
        self.repeatWindow = repeatWindow
        self.lastTap = lastTap
    }

    mutating func action(for band: Int?, at timestamp: TimeInterval) -> CanvasBandTapAction {
        if let lastTap,
           timestamp - lastTap.timestamp <= repeatWindow,
           lastTap.band == band {
            self.lastTap = nil
            if let band {
                return .focus(band)
            }
            return .resetViewport
        }

        lastTap = Entry(band: band, timestamp: timestamp)
        return .inspect(band)
    }

    mutating func reset() {
        lastTap = nil
    }
}

struct ImageCanvasView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var showImagePicker: Bool
    @Binding var showSamplePicker: Bool

    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gesturePan: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var isBreathing = false
    @State private var inspectedBand: Int? = nil
    @State private var bandTapTracker = CanvasBandTapTracker()

    private var displayImage: UIImage? {
        state.currentDisplayImage
    }

    private var inspectedBandSummary: CanvasBandSummary? {
        guard (state.activeMode == .value || state.activeMode == .color),
              let inspectedBand,
              let paletteIndex = state.paletteBands.firstIndex(of: inspectedBand),
              state.paletteColors.indices.contains(paletteIndex)
        else {
            return nil
        }

        let recipe = state.pigmentRecipes.flatMap { recipes in
            recipes.indices.contains(paletteIndex) ? recipes[paletteIndex] : nil
        }
        let title = PaletteColorNamer.name(for: state.paletteColors[paletteIndex])
            ?? recipe.map { PaletteColorNamer.name(for: $0.predictedColor) }
            ?? "Swatch"

        return CanvasBandSummary(
            band: inspectedBand,
            title: title,
            color: state.paletteColors[paletteIndex],
            recipe: recipe
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = displayImage {
                    zoomableCanvas(image: image, containerSize: geo.size)
                        .blur(radius: shouldDimCanvas ? 8 : 0)
                        .opacity(shouldDimCanvas ? 0.55 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: shouldDimCanvas)
                        .onChange(of: geo.size) { _, _ in
                            resetViewportIfNeeded()
                        }
                } else {
                    CanvasEmptyStateCard(
                        isBreathing: isBreathing,
                        onOpenPhoto: openPhotoPicker,
                        onOpenSamples: openSamplePicker
                    )
                    .onAppear {
                        guard !reduceMotion else { return }
                        isBreathing = true
                    }
                }

                if state.isProcessing {
                    processingOverlay
                }

                if let inspectedBandSummary {
                    CanvasBandSummaryCard(
                        summary: inspectedBandSummary,
                        isFocused: state.focusedBands.contains(inspectedBandSummary.band),
                        onToggleFocus: { state.toggleFocusedBand(inspectedBandSummary.band) },
                        onClose: dismissInspectedBand
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: state.isProcessing) { _, isProcessing in
            if isProcessing {
                inspectedBand = nil
                bandTapTracker.reset()
            }
        }
        .onChange(of: state.activeMode) { _, _ in
            inspectedBand = nil
            bandTapTracker.reset()
        }
    }

    private var shouldDimCanvas: Bool {
        state.isProcessing && !state.isSimplifying
    }

    private func zoomableCanvas(image: UIImage, containerSize: CGSize) -> some View {
        let combinedScale = currentScale * gestureScale
        let combinedOffset = CGSize(
            width: currentOffset.width + gesturePan.width,
            height: currentOffset.height + gesturePan.height
        )

        return StudyImageLayer(
            image: image,
            showsGrid: state.gridConfig.enabled,
            showsContours: state.contourConfig.enabled
                && state.depthConfig.enabled
                && !state.isEditingDepthThreshold
        )
        .contentShape(Rectangle())
        .scaleEffect(combinedScale)
        .offset(combinedOffset)
        .highPriorityGesture(
            SpatialTapGesture()
                .onEnded { value in
                    selectBand(
                        at: value.location,
                        image: image,
                        containerSize: containerSize
                    )
                }
        )
        .gesture(
            MagnificationGesture()
                .updating($gestureScale) { value, gestureState, _ in
                    gestureState = value
                }
                .onEnded { value in
                    let newScale = max(1.0, min(8.0, currentScale * value))
                    currentScale = newScale
                    if newScale == 1.0 {
                        currentOffset = .zero
                    } else {
                        currentOffset = clampedOffset(
                            currentOffset,
                            scale: newScale,
                            image: image,
                            container: containerSize
                        )
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .updating($gesturePan) { value, gestureState, _ in
                    gestureState = value.translation
                }
                .onEnded { value in
                    let proposed = CGSize(
                        width: currentOffset.width + value.translation.width,
                        height: currentOffset.height + value.translation.height
                    )
                    currentOffset = clampedOffset(
                        proposed,
                        scale: currentScale,
                        image: image,
                        container: containerSize
                    )
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(state.activeMode.label) study canvas")
        .accessibilityHint(canvasAccessibilityHint)
        .accessibilityIdentifier("canvas.image")
    }

    private var canvasAccessibilityHint: String {
        switch state.activeMode {
        case .value, .color:
            return "Pinch to zoom, drag to pan, tap once for swatch info, tap the same swatch again to focus, and double tap empty canvas to reset."
        case .original, .tonal:
            return "Pinch to zoom, drag to pan, and double tap to reset."
        }
    }

    private func clampedOffset(_ offset: CGSize, scale: CGFloat, image: UIImage, container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return offset }

        let imageAspect = image.size.width / image.size.height
        let containerAspect = container.width / container.height
        let renderedSize: CGSize

        if imageAspect > containerAspect {
            renderedSize = CGSize(width: container.width, height: container.width / imageAspect)
        } else {
            renderedSize = CGSize(width: container.height * imageAspect, height: container.height)
        }

        let maxX = max(0, renderedSize.width * (scale - 1) / 2)
        let maxY = max(0, renderedSize.height * (scale - 1) / 2)

        return CGSize(
            width: max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)

            VStack(spacing: 12) {
                if state.processingIsIndeterminate {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                } else {
                    ProgressView(value: state.processingProgress)
                        .tint(.white)
                        .frame(width: 188)
                }

                Text(processingDisplayLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(processingDisplayLabel)
        .accessibilityIdentifier("canvas.processing-overlay")
    }

    private var processingDisplayLabel: String {
        switch state.processingLabel {
        case "Loading…":
            return "Preparing image"
        case "Abstracting…":
            return "Abstracting image"
        case "Processing…":
            switch state.activeMode {
            case .original:
                return "Preparing image"
            case .tonal:
                return "Generating tonal study"
            case .value:
                return "Generating value study"
            case .color:
                return "Generating color study"
            }
        default:
            return state.processingLabel
        }
    }

    private func resetViewportIfNeeded() {
        guard currentScale > 1.0 else { return }
        resetViewport()
    }

    private func resetViewport() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            currentScale = 1.0
            currentOffset = .zero
        }
    }

    private func selectBand(
        at location: CGPoint,
        image: UIImage,
        containerSize: CGSize
    ) {
        let tappedBand = tappedBand(
            at: location,
            image: image,
            containerSize: containerSize
        )
        let action = bandTapTracker.action(
            for: tappedBand,
            at: ProcessInfo.processInfo.systemUptime
        )

        switch action {
        case .inspect(let band):
            inspectedBand = band

        case .focus(let band):
            inspectedBand = band
            if !state.focusedBands.contains(band) {
                state.toggleFocusedBand(band)
            }

        case .resetViewport:
            inspectedBand = nil
            resetViewport()
        }
    }

    private func tappedBand(
        at location: CGPoint,
        image: UIImage,
        containerSize: CGSize
    ) -> Int? {
        guard state.activeMode == .value || state.activeMode == .color else {
            return nil
        }

        let imageRect = transformedImageRect(
            for: image,
            in: containerSize,
            scale: currentScale,
            offset: currentOffset
        )
        guard imageRect.width > 0, imageRect.height > 0,
              imageRect.contains(location)
        else {
            return nil
        }

        let normalizedPoint = CGPoint(
            x: (location.x - imageRect.minX) / imageRect.width,
            y: (location.y - imageRect.minY) / imageRect.height
        )
        return state.band(atNormalizedPoint: normalizedPoint)
    }

    private func transformedImageRect(
        for image: UIImage,
        in containerSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> CGRect {
        let fittedRect = fittedImageRect(for: image, in: containerSize)
        let scaledWidth = fittedRect.width * scale
        let scaledHeight = fittedRect.height * scale

        return CGRect(
            x: fittedRect.midX - scaledWidth / 2 + offset.width,
            y: fittedRect.midY - scaledHeight / 2 + offset.height,
            width: scaledWidth,
            height: scaledHeight
        )
    }

    private func fittedImageRect(
        for image: UIImage,
        in containerSize: CGSize
    ) -> CGRect {
        guard containerSize.width > 0,
              containerSize.height > 0,
              image.size.width > 0,
              image.size.height > 0
        else {
            return .zero
        }

        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        let fittedSize: CGSize

        if imageAspect > containerAspect {
            fittedSize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspect
            )
        } else {
            fittedSize = CGSize(
                width: containerSize.height * imageAspect,
                height: containerSize.height
            )
        }

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func dismissInspectedBand() {
        inspectedBand = nil
        bandTapTracker.reset()
    }

    private func openPhotoPicker() {
        showImagePicker = true
    }

    private func openSamplePicker() {
        showSamplePicker = true
    }
}

private struct CanvasBandSummary {
    let band: Int
    let title: String
    let color: Color
    let recipe: PigmentRecipe?
}

private struct CanvasBandSummaryCard: View {
    let summary: CanvasBandSummary
    let isFocused: Bool
    let onToggleFocus: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(summary.color)
                    .frame(width: 44, height: 36)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    }

                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(action: onToggleFocus) {
                    FocusPill(isFocused: isFocused)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFocused ? "Remove focus from swatch" : "Focus swatch")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide swatch")
            }

            if let recipe = summary.recipe {
                RecipeView(recipe: recipe)
                    .foregroundStyle(.white)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.band-callout")
    }
}

struct StudyImageLayer: View {
    let image: UIImage
    let showsGrid: Bool
    var showsContours: Bool = false

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsGrid {
                GridOverlayView(image: image)
            }

            if showsContours {
                ContourOverlayView(image: image)
            }
        }
    }
}

private struct CanvasEmptyStateCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(UnlockManager.self) private var unlockManager

    let isBreathing: Bool
    let onOpenPhoto: () -> Void
    let onOpenSamples: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(.white.opacity(0.88))
                .scaleEffect(isBreathing ? 1.06 : 0.98)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 4.0).repeatForever(autoreverses: true),
                    value: isBreathing
                )

            VStack(spacing: 10) {
                Text("Build a study from any reference")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Choose a photo or sample, simplify the big shapes, compare versions, and extract value maps or pigment mixes.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button(action: onOpenPhoto) {
                    Label(
                        unlockManager.isUnlocked ? "Choose Photo" : "Choose Photo",
                        systemImage: unlockManager.isUnlocked ? "photo" : "lock.fill"
                    )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(unlockManager.isUnlocked ? "Choose Photo" : "Choose Photo (requires unlock)")
                .accessibilityIdentifier("canvas.empty.library")

                Button(action: onOpenSamples) {
                    Label("Browse Samples", systemImage: "sparkles.rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityIdentifier("canvas.empty.samples")
            }
        }
        .frame(maxWidth: 390)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas.empty-state")
    }
}

#Preview("Empty Canvas") {
    ImageCanvasView(
        showImagePicker: .constant(false),
        showSamplePicker: .constant(false)
    )
    .environment(AppState())
    .environment(UnlockManager())
}

private struct ImageCanvasPreviewHarness: View {
    @State private var state = AppState()

    init(mode: RefPlaneMode, depthEnabled: Bool) {
        let previewState = AppState()
        let previewImage = UIImage(named: "sample-landscape")
            ?? UIImage(systemName: "photo")!

        previewState.originalImage = previewImage
        previewState.sourceImage = previewImage
        previewState.activeMode = mode
        previewState.depthConfig.enabled = depthEnabled

        if depthEnabled {
            previewState.contourConfig.enabled = true
        }

        _state = State(initialValue: previewState)
    }

    var body: some View {
        ImageCanvasView(
            showImagePicker: .constant(false),
            showSamplePicker: .constant(false)
        )
        .environment(state)
        .environment(UnlockManager())
    }
}

#Preview("Color Canvas") {
    ImageCanvasPreviewHarness(mode: .color, depthEnabled: false)
}

#Preview("Depth Canvas") {
    ImageCanvasPreviewHarness(mode: .value, depthEnabled: true)
}
