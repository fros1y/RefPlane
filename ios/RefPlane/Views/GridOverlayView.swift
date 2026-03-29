import SwiftUI

struct GridOverlayView: View {
    @EnvironmentObject private var state: AppState
    var image: UIImage? = nil
    private let lineWidth: CGFloat = 0.5

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let config = state.gridConfig
                guard config.enabled else { return }
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

                // Clip all drawing to the fitted image rect so lines don't
                // bleed into letterbox areas.
                let imageRect = CGRect(x: originX, y: originY,
                                       width: imgSize.width, height: imgSize.height)
                ctx.clip(to: Path(imageRect))

                let layoutSize = sourceImage?.size ?? imgSize
                let segments = GridLineColorResolver.resolvedSegments(
                    config: config,
                    image: sourceImage,
                    segments: GridLineColorResolver.normalizedSegments(
                        config: config,
                        imageSize: layoutSize
                    )
                )
                let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .square)

                for resolvedSegment in segments {
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
