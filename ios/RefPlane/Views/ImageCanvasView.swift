import SwiftUI

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

    private var displayImage: UIImage? {
        state.currentDisplayImage
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
            }
        }
        .environment(\.colorScheme, .dark)
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
        .scaleEffect(combinedScale)
        .offset(combinedOffset)
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
        .onTapGesture(count: 2, perform: resetViewport)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(state.activeMode.label) study canvas")
        .accessibilityHint("Pinch to zoom, drag to pan, and double tap to reset.")
        .accessibilityIdentifier("canvas.image")
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

    private func openPhotoPicker() {
        showImagePicker = true
    }

    private func openSamplePicker() {
        showSamplePicker = true
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
                    Label("Choose Photo", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
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
    }
}

#Preview("Color Canvas") {
    ImageCanvasPreviewHarness(mode: .color, depthEnabled: false)
}

#Preview("Depth Canvas") {
    ImageCanvasPreviewHarness(mode: .value, depthEnabled: true)
}
