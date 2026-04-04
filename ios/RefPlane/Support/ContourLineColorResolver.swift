import SwiftUI
import UIKit

enum ContourLineColorResolver {

    static func resolvedSegments(
        config: ContourConfig,
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
            let proxy = GridConfig(
                enabled: true,
                divisions: 0,
                showDiagonals: false,
                lineStyle: .autoContrast,
                customColor: config.customColor,
                opacity: config.opacity
            )
            return GridLineColorResolver.resolvedSegments(
                config: proxy,
                image: image,
                segments: segments
            )
        }
    }
}
