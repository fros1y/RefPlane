import SwiftUI


struct CompareSliderView: View {
    @EnvironmentObject private var state: AppState
    let beforeImage: UIImage
    let afterImage: UIImage

    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                StudyImageLayer(image: afterImage, showsGrid: state.gridConfig.enabled,
                                showsContours: state.contourConfig.enabled
                                    && state.depthConfig.enabled
                                    && !state.isEditingDepthThreshold)
                    .frame(width: geo.size.width, height: geo.size.height)

                StudyImageLayer(image: beforeImage, showsGrid: false, showsContours: false)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: geo.size.width * splitFraction)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                CompareDividerHandle(splitFraction: $splitFraction, width: geo.size.width, height: geo.size.height)

                VStack {
                    HStack {
                        CompareTag(title: "Original", icon: "photo")
                            .padding(.leading, 12)
                        Spacer()
                        CompareTag(title: "Processed", icon: "wand.and.stars")
                            .padding(.trailing, 12)
                    }
                    .padding(.top, 10)

                    Spacer()
                }

                if state.isProcessing {
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

                            Text(state.processingLabel)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .ignoresSafeArea()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(state.processingLabel)
                }
            }
            .background(Color.black)
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct CompareDividerHandle: View {
    @Binding var splitFraction: CGFloat
    let width: CGFloat
    let height: CGFloat

    @GestureState private var isDragging = false

    var body: some View {
        let xPosition = width * splitFraction

        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2)

            Circle()
                .fill(.regularMaterial)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
                .scaleEffect(isDragging ? 1.1 : 1.0)
                .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 10 : 3, x: 0, y: isDragging ? 5 : 2)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
        }
        .frame(height: height)
        .position(x: xPosition, y: height / 2)
        .gesture(
            DragGesture()
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    let fraction = value.location.x / width
                    splitFraction = max(0.02, min(0.98, fraction))
                }
        )
        .modifier(SensoryFeedback17(splitFraction: splitFraction))
        .accessibilityElement()
        .accessibilityLabel("Comparison divider")
        .accessibilityValue("\(Int(splitFraction * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                splitFraction = min(0.98, splitFraction + 0.05)
            case .decrement:
                splitFraction = max(0.02, splitFraction - 0.05)
            @unknown default:
                break
            }
        }
    }
}

private struct CompareTag: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
    }
}
private struct SensoryFeedback17: ViewModifier {
    let splitFraction: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.sensoryFeedback(.selection, trigger: splitFraction)
        } else {
            content
        }
    }
}
