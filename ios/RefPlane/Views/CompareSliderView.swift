import SwiftUI

struct CompareSliderView: View {
    @Environment(AppState.self) private var state

    let beforeImage: UIImage
    let afterImage: UIImage

    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                StudyImageLayer(
                    image: afterImage,
                    showsGrid: state.transform.gridConfig.enabled,
                    showsContours: state.transform.contourConfig.enabled
                        && state.depth.depthConfig.enabled
                        && !state.depth.isEditingDepthThreshold
                )
                .frame(width: geo.size.width, height: geo.size.height)

                StudyImageLayer(image: beforeImage, showsGrid: false, showsContours: false)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: geo.size.width * splitFraction)
                    }

                CompareDividerHandle(
                    splitFraction: $splitFraction,
                    width: geo.size.width,
                    height: geo.size.height
                )

                compareLabels

                if state.processing.isProcessing {
                    compareProcessingOverlay
                }
            }
            .background(Color.black)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("compare.canvas")
    }

    private var processedTitle: String {
        if state.transform.activeMode == .original {
            return state.transform.abstractionStrength > 0 ? "Abstracted" : "Original"
        }
        return state.transform.activeMode.label
    }

    private var processedIcon: String {
        if state.transform.activeMode == .original {
            return state.transform.abstractionStrength > 0 ? "wand.and.stars" : "photo"
        }
        return state.transform.activeMode.iconName
    }

    private var compareLabels: some View {
        VStack {
            HStack {
                CompareTag(title: "Original", icon: "photo")
                    .accessibilityIdentifier("compare.label.original")
                Spacer()
                CompareTag(title: processedTitle, icon: processedIcon)
                    .accessibilityIdentifier("compare.label.processed")
            }
            .padding(.horizontal, 20)
            .padding(.top, 86)

            Spacer(minLength: 0)
        }
    }

    private var compareProcessingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)

            VStack(spacing: 12) {
                if state.processing.isIndeterminate {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                } else {
                    ProgressView(value: state.processing.progress)
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
        .accessibilityIdentifier("compare.processing-overlay")
    }

    private var processingDisplayLabel: String {
        switch state.processing.label {
        case "Loading…":
            return "Preparing image"
        case "Abstracting…":
            return "Abstracting image"
        case "Estimating depth…":
            return "Estimating depth"
        case "Applying depth…":
            return "Applying depth"
        case "Rendering painter's kit…":
            return "Rendering painter's kit"
        case "Processing…":
            switch state.transform.activeMode {
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
            return state.processing.label
        }
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
                .fill(Color.white.opacity(0.92))
                .frame(width: 2)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 0)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
                .scaleEffect(isDragging ? 1.08 : 1.0)
                .shadow(
                    color: .black.opacity(isDragging ? 0.28 : 0.16),
                    radius: isDragging ? 16 : 8,
                    x: 0,
                    y: isDragging ? 8 : 4
                )
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        .modifier(SensoryFeedback17(splitFraction: splitFraction))
        .accessibilityElement()
        .accessibilityLabel("Comparison divider")
        .accessibilityValue("\(Int(splitFraction * 100)) percent")
        .accessibilityIdentifier("compare.divider")
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
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
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
