import SwiftUI

struct GridOverlayView: View {
    @EnvironmentObject private var state: AppState
    var image: UIImage? = nil

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let config = state.gridConfig
                guard config.enabled else { return }

                let imgSize: CGSize
                if let img = image ?? state.currentDisplayImage {
                    let aspect = img.size.width / img.size.height
                    let fitW   = min(size.width, size.height * aspect)
                    let fitH   = fitW / aspect
                    imgSize    = CGSize(width: fitW, height: fitH)
                } else {
                    imgSize    = size
                }

                let originX = (size.width  - imgSize.width)  / 2
                let originY = (size.height - imgSize.height) / 2

                let lineColor = resolveLineColor(config: config,
                                                 ctx: ctx,
                                                 origin: CGPoint(x: originX, y: originY),
                                                 size: imgSize)

                let cellW: CGFloat
                let cellH: CGFloat
                let div = CGFloat(config.divisions)

                switch config.cellAspect {
                case .square:
                    let shortEdge = min(imgSize.width, imgSize.height)
                    cellW = shortEdge / div
                    cellH = cellW
                case .matchImage:
                    cellW = imgSize.width  / div
                    cellH = imgSize.height / div
                }

                let cols = Int((imgSize.width  / cellW).rounded(.up))
                let rows = Int((imgSize.height / cellH).rounded(.up))

                var path = Path()

                // Clip all drawing to the fitted image rect so lines don't
                // bleed into letterbox areas.
                let imageRect = CGRect(x: originX, y: originY,
                                       width: imgSize.width, height: imgSize.height)
                ctx.clip(to: Path(imageRect))

                // Vertical lines
                for col in 0...cols {
                    let x = originX + CGFloat(col) * cellW
                    path.move(to:    CGPoint(x: x, y: originY))
                    path.addLine(to: CGPoint(x: x, y: originY + imgSize.height))
                }

                // Horizontal lines
                for row in 0...rows {
                    let y = originY + CGFloat(row) * cellH
                    path.move(to:    CGPoint(x: originX,                  y: y))
                    path.addLine(to: CGPoint(x: originX + imgSize.width,  y: y))
                }

                // Cell diagonals and center lines
                if config.showDiagonals || config.showCenterLines {
                    for col in 0..<cols {
                        for row in 0..<rows {
                            let cx = originX + CGFloat(col) * cellW
                            let cy = originY + CGFloat(row) * cellH
                            let cw = min(cellW, imgSize.width  - cx + originX)
                            let ch = min(cellH, imgSize.height - cy + originY)

                            if config.showDiagonals {
                                path.move(to:    CGPoint(x: cx,      y: cy))
                                path.addLine(to: CGPoint(x: cx + cw, y: cy + ch))
                                path.move(to:    CGPoint(x: cx + cw, y: cy))
                                path.addLine(to: CGPoint(x: cx,      y: cy + ch))
                            }
                            if config.showCenterLines {
                                path.move(to:    CGPoint(x: cx + cw / 2, y: cy))
                                path.addLine(to: CGPoint(x: cx + cw / 2, y: cy + ch))
                                path.move(to:    CGPoint(x: cx,           y: cy + ch / 2))
                                path.addLine(to: CGPoint(x: cx + cw,      y: cy + ch / 2))
                            }
                        }
                    }
                }

                ctx.stroke(path,
                           with: .color(lineColor.opacity(config.opacity)),
                           lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func resolveLineColor(config: GridConfig,
                                  ctx: GraphicsContext,
                                  origin: CGPoint,
                                  size: CGSize) -> Color {
        switch config.lineStyle {
        case .black:        return .black
        case .white:        return .white
        case .custom:       return config.customColor
        case .autoContrast: return .white  // default; ideally sample background brightness
        }
    }
}
