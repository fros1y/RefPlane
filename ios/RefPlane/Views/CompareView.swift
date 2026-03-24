import SwiftUI

/// Before/after split-view with draggable divider.
struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    let beforeImage: UIImage
    let afterImage:  UIImage

    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // After (right side / full width underneath)
                Image(uiImage: afterImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                // Before (left side, clipped)
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

                // Divider handle
                let divX = geo.size.width * splitFraction
                ZStack {
                    Rectangle()
                        .frame(width: 2)
                        .foregroundColor(.white.opacity(0.9))

                    Circle()
                        .fill(Color.white)
                        .frame(width: 34, height: 34)
                        .shadow(radius: 4)
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                        )
                }
                .frame(height: geo.size.height)
                .position(x: divX, y: geo.size.height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let fraction = value.location.x / geo.size.width
                            splitFraction = max(0.02, min(0.98, fraction))
                        }
                )

                // Labels
                VStack {
                    HStack {
                        Label("Before", systemImage: "photo")
                            .font(.caption)
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .padding(.leading, 10)
                        Spacer()
                        Label("After", systemImage: "wand.and.stars")
                            .font(.caption)
                            .padding(5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .padding(.trailing, 10)
                    }
                    .foregroundColor(.white)
                    .padding(.top, 48)
                    Spacer()
                }
            }
            .background(Color.black)
            .overlay(alignment: .topTrailing) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(16)
                }
            }
        }
        .ignoresSafeArea()
    }
}
