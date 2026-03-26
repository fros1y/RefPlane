import SwiftUI

// MARK: - Pinch-to-zoom + pan canvas with grid overlay

struct ImageCanvasView: View {
    @EnvironmentObject private var state: AppState
    @Binding var showImagePicker: Bool

    @GestureState private var gestureScale: CGFloat     = 1.0
    @GestureState private var gesturePan: CGSize        = .zero
    @State private var currentScale: CGFloat            = 1.0
    @State private var currentOffset: CGSize            = .zero

    private var displayImage: UIImage? {
        if state.showCompare { return nil }  // handled by CompareView sheet
        return state.currentDisplayImage
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Main content layer
                ZStack {
                    Color.black.ignoresSafeArea()

                    if let img = displayImage {
                        let combinedScale  = currentScale * gestureScale
                        let combinedOffset = CGSize(
                            width:  currentOffset.width  + gesturePan.width,
                            height: currentOffset.height + gesturePan.height
                        )

                        ZStack {
                            Image(uiImage: img)
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
                                .updating($gestureScale) { value, state, _ in state = value }
                                .onEnded { value in
                                    currentScale = max(1.0, min(8.0, currentScale * value))
                                    if currentScale == 1.0 { currentOffset = .zero }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .updating($gesturePan) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    currentOffset = CGSize(
                                        width:  currentOffset.width  + value.translation.width,
                                        height: currentOffset.height + value.translation.height
                                    )
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                currentScale  = 1.0
                                currentOffset = .zero
                            }
                        }

                    } else {
                        // Empty state — tap to open image
                        Button(action: { showImagePicker = true }) {
                            VStack(spacing: 16) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white.opacity(0.3))
                                Text("Tap to open an image")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Processing overlay
                    if state.isProcessing {
                        ZStack {
                            Color.black.opacity(0.45)
                            VStack(spacing: 10) {
                                if state.processingIsIndeterminate {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(1.2)
                                } else {
                                    ProgressView(value: state.processingProgress)
                                        .tint(.white)
                                        .frame(width: 160)
                                }
                                Text(state.processingLabel)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .ignoresSafeArea()
                    }
                }

                // Back button overlay (when image is loaded)
                if state.originalImage != nil {
                    Button(action: { showImagePicker = true }) {
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 12)
                    .padding(.top, 12)
                }
            }
        }
    }
}
