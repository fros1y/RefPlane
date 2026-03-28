import SwiftUI

struct ImageCanvasView: View {
    @EnvironmentObject private var state: AppState
    @Binding var showImagePicker: Bool

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
                        .blur(radius: state.isProcessing ? 8 : 0)
                        .opacity(state.isProcessing ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: state.isProcessing)
                } else {
                    emptyState
                }

                if state.isProcessing {
                    processingOverlay
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func zoomableCanvas(image: UIImage, containerSize: CGSize) -> some View {
        let combinedScale = currentScale * gestureScale
        let combinedOffset = CGSize(
            width: currentOffset.width + gesturePan.width,
            height: currentOffset.height + gesturePan.height
        )

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state.gridConfig.enabled {
                GridOverlayView()
            }
        }
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
                        currentOffset = clampedOffset(currentOffset, scale: newScale, image: image, container: containerSize)
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
                    currentOffset = clampedOffset(proposed, scale: currentScale, image: image, container: containerSize)
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                currentScale = 1.0
                currentOffset = .zero
            }
        }
    }

    /// Returns `offset` clamped so the image stays visible within the container.
    /// Uses the image's aspect ratio to compute the actual rendered bounds.
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

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
                .scaleEffect(isBreathing ? 1.05 : 1.0)
                .animation(
                    .easeInOut(duration: 4.0).repeatForever(autoreverses: true),
                    value: isBreathing
                )
                .onAppear {
                    isBreathing = true
                }

            VStack(spacing: 6) {
                Text("Choose a reference image")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Prepare tonal, value, and color studies from one image.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            Button("Open") {
                showImagePicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14))
        }
        .padding(24)
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.24)

            VStack(spacing: 12) {
                if state.processingIsIndeterminate {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                } else {
                    ProgressView(value: state.processingProgress)
                        .tint(.white)
                        .frame(width: 180)
                }

                Text(processingDisplayLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(processingDisplayLabel)
    }

    private var processingDisplayLabel: String {
        switch state.processingLabel {
        case "Loading…":
            return "Preparing image"
        case "Simplifying…":
            return "Simplifying image"
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
}
