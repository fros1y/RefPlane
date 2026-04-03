import SwiftUI

struct ContourOverlayView: View {
    @Environment(AppState.self) private var state
    var image: UIImage? = nil
    private let lineWidth: CGFloat = 0.6

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let config = state.contourConfig
                guard config.enabled else { return }
                let segments = state.contourSegments
                guard !segments.isEmpty else { return }
                let sourceImage = image ?? state.currentDisplayImage

                let imgSize: CGSize
                if let img = sourceImage {
                    let aspect = img.size.width / img.size.height
                    let fitW   = min(size.width, size.height * aspect)
                    let fitH   = fitW / aspect
                    imgSize    = CGSize(width: fitW, height: fitH)
                } else {
                    imgSize    = size
                }

                let originX = (size.width  - imgSize.width)  / 2
                let originY = (size.height - imgSize.height) / 2

                let imageRect = CGRect(x: originX, y: originY,
                                       width: imgSize.width, height: imgSize.height)
                ctx.clip(to: Path(imageRect))

                let resolved = ContourLineColorResolver.resolvedSegments(
                    config: config,
                    image: sourceImage,
                    segments: segments
                )
                let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

                for resolvedSegment in resolved {
                    let mappedSegment = resolvedSegment.segment.mapped(to: imageRect)
                    var path = Path()
                    path.move(to: mappedSegment.start)
                    path.addLine(to: mappedSegment.end)
                    ctx.stroke(
                        path,
                        with: .color(resolvedSegment.color.opacity(config.opacity)),
                        style: strokeStyle
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
