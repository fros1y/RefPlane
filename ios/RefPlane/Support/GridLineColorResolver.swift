import SwiftUI
import UIKit

struct GridLineSegment: Equatable {
    let start: CGPoint
    let end: CGPoint

    var isDegenerate: Bool {
        start == end
    }

    func point(at progress: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    func mapped(to rect: CGRect) -> GridLineSegment {
        GridLineSegment(
            start: CGPoint(
                x: rect.minX + start.x * rect.width,
                y: rect.minY + start.y * rect.height
            ),
            end: CGPoint(
                x: rect.minX + end.x * rect.width,
                y: rect.minY + end.y * rect.height
            )
        )
    }
}

struct ResolvedGridLineSegment {
    let segment: GridLineSegment
    let color: Color
    let tone: GridLineTone?

    init(segment: GridLineSegment, color: Color) {
        self.segment = segment
        self.color = color
        self.tone = nil
    }

    init(segment: GridLineSegment, tone: GridLineTone) {
        self.segment = segment
        self.color = tone.color
        self.tone = tone
    }
}

enum GridLineTone: Equatable, Sendable {
    case black
    case white

    var color: Color {
        switch self {
        case .black:
            return .black
        case .white:
            return .white
        }
    }

    var luminance: Double {
        switch self {
        case .black:
            return 0
        case .white:
            return 1
        }
    }
}

enum GridLineColorResolver {
    static func normalizedSegments(config: GridConfig, imageSize: CGSize) -> [GridLineSegment] {
        guard config.divisions > 0, imageSize.width > 0, imageSize.height > 0 else { return [] }

        let div = CGFloat(config.divisions)
        let shortEdge = min(imageSize.width, imageSize.height)
        let cellW = shortEdge / div
        let cellH = cellW

        let cols = Int((imageSize.width / cellW).rounded(.up))
        let rows = Int((imageSize.height / cellH).rounded(.up))
        var segments: [GridLineSegment] = []

        for col in 0...cols {
            let x = min(CGFloat(col) * cellW / imageSize.width, 1)
            segments.append(GridLineSegment(
                start: CGPoint(x: x, y: 0),
                end: CGPoint(x: x, y: 1)
            ))
        }

        for row in 0...rows {
            let y = min(CGFloat(row) * cellH / imageSize.height, 1)
            segments.append(GridLineSegment(
                start: CGPoint(x: 0, y: y),
                end: CGPoint(x: 1, y: y)
            ))
        }

        if config.showDiagonals {
            for col in 0..<cols {
                for row in 0..<rows {
                    let originX = CGFloat(col) * cellW / imageSize.width
                    let originY = CGFloat(row) * cellH / imageSize.height
                    let width = min(cellW / imageSize.width, 1 - originX)
                    let height = min(cellH / imageSize.height, 1 - originY)
                    guard width > 0, height > 0 else { continue }

                    if config.showDiagonals {
                        segments.append(GridLineSegment(
                            start: CGPoint(x: originX, y: originY),
                            end: CGPoint(x: originX + width, y: originY + height)
                        ))
                        segments.append(GridLineSegment(
                            start: CGPoint(x: originX + width, y: originY),
                            end: CGPoint(x: originX, y: originY + height)
                        ))
                    }
                }
            }
        }

        return segments.filter { !$0.isDegenerate }
    }

    static func resolvedSegments(
        config: GridConfig,
        image: UIImage?,
        segments: [GridLineSegment]
    ) -> [ResolvedGridLineSegment] {
        switch config.lineStyle {
        case .black:
            return segments.map { ResolvedGridLineSegment(segment: $0, color: .black) }
        case .white:
            return segments.map { ResolvedGridLineSegment(segment: $0, color: .white) }
        case .custom:
            return segments.map { ResolvedGridLineSegment(segment: $0, color: config.customColor) }
        case .autoContrast:
            guard let sampler = ImageLuminanceSampler(image: image) else {
                return segments.map { ResolvedGridLineSegment(segment: $0, tone: .white) }
            }
            return segments.flatMap { adaptiveSegments(for: $0, sampler: sampler) }
        }
    }

    static func resolvedColor(config: GridConfig, image: UIImage?) -> Color {
        switch config.lineStyle {
        case .black:
            return .black
        case .white:
            return .white
        case .custom:
            return config.customColor
        case .autoContrast:
            return autoContrastTone(forAverageLuminance: image?.averagePerceivedLuminance()).color
        }
    }

    static func autoContrastTone(forAverageLuminance averageLuminance: Double?) -> GridLineTone {
        guard let averageLuminance else { return .white }

        let blackContrast = contrastDistance(from: averageLuminance, to: .black)
        let whiteContrast = contrastDistance(from: averageLuminance, to: .white)
        return blackContrast >= whiteContrast ? .black : .white
    }

    static func contrastDistance(from backgroundLuminance: Double, to tone: GridLineTone) -> Double {
        abs(backgroundLuminance - tone.luminance)
    }

    private static func adaptiveSegments(
        for segment: GridLineSegment,
        sampler: ImageLuminanceSampler
    ) -> [ResolvedGridLineSegment] {
        let pixelLength = sampler.pixelLength(of: segment)
        let preferredSegmentLength = min(48.0, max(1.0, Double(min(sampler.width, sampler.height))))
        let chunkCount = max(1, Int(ceil(pixelLength / preferredSegmentLength)))

        var resolved: [(segment: GridLineSegment, tone: GridLineTone)] = []
        resolved.reserveCapacity(chunkCount)

        for chunkIndex in 0..<chunkCount {
            let startProgress = CGFloat(chunkIndex) / CGFloat(chunkCount)
            let endProgress = CGFloat(chunkIndex + 1) / CGFloat(chunkCount)
            let chunk = GridLineSegment(
                start: segment.point(at: startProgress),
                end: segment.point(at: endProgress)
            )
            let tone = autoContrastTone(
                forAverageLuminance: sampler.averageLuminance(around: chunk)
            )

            if let lastIndex = resolved.indices.last, resolved[lastIndex].tone == tone {
                resolved[lastIndex].segment = GridLineSegment(
                    start: resolved[lastIndex].segment.start,
                    end: chunk.end
                )
            } else {
                resolved.append((segment: chunk, tone: tone))
            }
        }

        return resolved.map { ResolvedGridLineSegment(segment: $0.segment, tone: $0.tone) }
    }
}

private struct ImageLuminanceSampler {
    let pixels: [UInt8]
    let width: Int
    let height: Int

    init?(image: UIImage?) {
        guard let image, let (pixels, width, height) = image.toPixelData(), width > 0, height > 0 else {
            return nil
        }

        self.pixels = pixels
        self.width = width
        self.height = height
    }

    func averageLuminance(around segment: GridLineSegment) -> Double? {
        let start = pixelPoint(for: segment.start)
        let end = pixelPoint(for: segment.end)
        let pixelLength = hypot(end.x - start.x, end.y - start.y)
        let sampleCount = max(1, Int(ceil(pixelLength / 8.0)))
        let radius = pixelLength < 3 ? 0 : 1

        var total = 0.0
        var count = 0

        for sampleIndex in 0..<sampleCount {
            let progress = (CGFloat(sampleIndex) + 0.5) / CGFloat(sampleCount)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            let centerX = Int(point.x.rounded())
            let centerY = Int(point.y.rounded())

            for offsetY in -radius...radius {
                for offsetX in -radius...radius {
                    total += luminanceAt(x: centerX + offsetX, y: centerY + offsetY)
                    count += 1
                }
            }
        }

        guard count > 0 else { return nil }
        return total / Double(count)
    }

    func pixelLength(of segment: GridLineSegment) -> Double {
        let start = pixelPoint(for: segment.start)
        let end = pixelPoint(for: segment.end)
        return Double(hypot(end.x - start.x, end.y - start.y))
    }

    func averagePerceivedLuminance(maxSampleCount: Int = 4096) -> Double? {
        guard width > 0, height > 0 else { return nil }

        let sampleStep = max(1, Int(sqrt(Double(width * height) / Double(maxSampleCount))))
        var totalLuminance = 0.0
        var sampleCount = 0

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let base = (y * width + x) * 4
                let r = Float(pixels[base]) / 255.0
                let g = Float(pixels[base + 1]) / 255.0
                let b = Float(pixels[base + 2]) / 255.0

                let rl = linearizeSRGB(r)
                let gl = linearizeSRGB(g)
                let bl = linearizeSRGB(b)
                let luminance = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl

                totalLuminance += Double(luminance)
                sampleCount += 1
                x += sampleStep
            }
            y += sampleStep
        }

        guard sampleCount > 0 else { return nil }
        return totalLuminance / Double(sampleCount)
    }

    private func pixelPoint(for normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: CGFloat(width - 1) * normalizedPoint.x,
            y: CGFloat(height - 1) * normalizedPoint.y
        )
    }

    private func luminanceAt(x: Int, y: Int) -> Double {
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)
        let base = (clampedY * width + clampedX) * 4
        let r = Float(pixels[base]) / 255.0
        let g = Float(pixels[base + 1]) / 255.0
        let b = Float(pixels[base + 2]) / 255.0

        let rl = linearizeSRGB(r)
        let gl = linearizeSRGB(g)
        let bl = linearizeSRGB(b)
        return Double(0.2126 * rl + 0.7152 * gl + 0.0722 * bl)
    }
}

private extension UIImage {
    func averagePerceivedLuminance(maxSampleCount: Int = 4096) -> Double? {
        ImageLuminanceSampler(image: self)?.averagePerceivedLuminance(maxSampleCount: maxSampleCount)
    }
}
