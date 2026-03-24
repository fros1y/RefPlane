import SwiftUI

/// Non-destructive crop view. Normalised rect (0..1).
struct CropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onConfirm: (CGRect) -> Void

    @State private var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var dragCorner: Corner? = nil

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        CropOverlay(
                            cropRect: $cropRect,
                            imageSize: fittedImageSize(in: geo.size)
                        )
                    )
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 20) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Button(action: {
                        onConfirm(cropRect)
                        dismiss()
                    }) {
                        Text("Apply Crop")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    Button(action: { cropRect = CGRect(x: 0, y: 0, width: 1, height: 1) }) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func fittedImageSize(in containerSize: CGSize) -> CGSize {
        let aspect = image.size.width / image.size.height
        let fitW   = min(containerSize.width, containerSize.height * aspect)
        let fitH   = fitW / aspect
        return CGSize(width: fitW, height: fitH)
    }
}

// MARK: - Crop overlay with corner handles

private struct CropOverlay: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize

    // Convert normalised rect to screen-space rect within fitted image
    private func screenRect(in containerSize: CGSize) -> CGRect {
        let originX = (containerSize.width  - imageSize.width)  / 2
        let originY = (containerSize.height - imageSize.height) / 2
        return CGRect(
            x:      originX + cropRect.minX * imageSize.width,
            y:      originY + cropRect.minY * imageSize.height,
            width:  cropRect.width  * imageSize.width,
            height: cropRect.height * imageSize.height
        )
    }

    var body: some View {
        GeometryReader { geo in
            let sRect = screenRect(in: geo.size)
            ZStack {
                // Dim outside crop
                Color.black.opacity(0.5)
                    .mask(
                        Rectangle()
                            .overlay(
                                Rectangle()
                                    .frame(width: sRect.width, height: sRect.height)
                                    .position(x: sRect.midX, y: sRect.midY)
                                    .blendMode(.destinationOut)
                            )
                    )
                    .allowsHitTesting(false)

                // Crop border
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: sRect.width, height: sRect.height)
                    .position(x: sRect.midX, y: sRect.midY)
                    .allowsHitTesting(false)

                // Corner handles: (hx, hy) 0=min, 1=max
                let corners: [(hx: Int, hy: Int, id: Int)] = [
                    (0, 0, 0), (1, 0, 1), (0, 1, 2), (1, 1, 3)
                ]
                ForEach(corners, id: \.id) { corner in
                    let hx = corner.hx, hy = corner.hy
                    let hPos = CGPoint(
                        x: sRect.minX + CGFloat(hx) * sRect.width,
                        y: sRect.minY + CGFloat(hy) * sRect.height
                    )
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .position(hPos)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let normX = (value.location.x - (geo.size.width  - imageSize.width)  / 2) / imageSize.width
                                    let normY = (value.location.y - (geo.size.height - imageSize.height) / 2) / imageSize.height
                                    let nx = max(0, min(1, normX))
                                    let ny = max(0, min(1, normY))
                                    var r = cropRect
                                    if hx == 0 && hy == 0 {
                                        let maxX = r.maxX - 0.05; let maxY = r.maxY - 0.05
                                        r.origin.x = min(nx, maxX); r.origin.y = min(ny, maxY)
                                        r.size.width  = r.maxX - r.origin.x
                                        r.size.height = r.maxY - r.origin.y
                                    } else if hx == 1 && hy == 0 {
                                        let minX = r.minX + 0.05; let maxY = r.maxY - 0.05
                                        r.size.width = max(0.05, nx - r.minX)
                                        r.origin.y = min(ny, maxY)
                                        r.size.height = r.maxY - r.origin.y
                                    } else if hx == 0 && hy == 1 {
                                        let maxX = r.maxX - 0.05; let minY = r.minY + 0.05
                                        r.origin.x = min(nx, maxX)
                                        r.size.width = r.maxX - r.origin.x
                                        r.size.height = max(0.05, ny - r.minY)
                                    } else {
                                        r.size.width  = max(0.05, nx - r.minX)
                                        r.size.height = max(0.05, ny - r.minY)
                                    }
                                    cropRect = r
                                }
                        )
                }
            }
        }
    }
}
