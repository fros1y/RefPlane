import SwiftUI

struct ImageCanvasView: View {
    @EnvironmentObject private var state: AppState
    @Binding var showImagePicker: Bool

    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gesturePan: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero

    private var displayImage: UIImage? {
        state.currentDisplayImage
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = displayImage {
                    zoomableCanvas(image: image)
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

    private func zoomableCanvas(image: UIImage) -> some View {
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
                    currentScale = max(1.0, min(8.0, currentScale * value))
                    if currentScale == 1.0 {
                        currentOffset = .zero
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .updating($gesturePan) { value, gestureState, _ in
                    gestureState = value.translation
                }
                .onEnded { value in
                    currentOffset = CGSize(
                        width: currentOffset.width + value.translation.width,
                        height: currentOffset.height + value.translation.height
                    )
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                currentScale = 1.0
                currentOffset = .zero
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))

            VStack(spacing: 6) {
                Text("Choose a reference image")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Prepare tonal, value, and color studies from one image.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            Button("Open Photos") {
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
