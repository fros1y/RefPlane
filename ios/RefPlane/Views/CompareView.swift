import SwiftUI

struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    let beforeImage: UIImage
    let afterImage: UIImage

    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        compareCanvas(topPadding: 48)
            .overlay(alignment: .topTrailing) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(16)
                }
                .accessibilityLabel("Close comparison")
            }
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }

    private func compareCanvas(topPadding: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Image(uiImage: afterImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                if state.gridConfig.enabled {
                    GridOverlayView(image: afterImage)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                Image(uiImage: beforeImage)
                    .resizable()
                    .scaledToFit()
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
                    .padding(.top, topPadding)

                    Spacer()
                }
            }
            .background(Color.black)
        }
    }
}

struct CompareSliderView: View {
    @EnvironmentObject private var state: AppState
    let beforeImage: UIImage
    let afterImage: UIImage

    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Image(uiImage: afterImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                if state.gridConfig.enabled {
                    GridOverlayView(image: afterImage)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                Image(uiImage: beforeImage)
                    .resizable()
                    .scaledToFit()
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
        }
        .frame(height: height)
        .position(x: xPosition, y: height / 2)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let fraction = value.location.x / width
                    splitFraction = max(0.02, min(0.98, fraction))
                }
        )
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
