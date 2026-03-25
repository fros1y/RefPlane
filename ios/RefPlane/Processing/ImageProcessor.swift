import UIKit
import SwiftUI

// MARK: - Processing result

struct ProcessingResult {
    let image: UIImage
    let palette: [Color]
    let paletteBands: [Int]

    static let empty = ProcessingResult(image: UIImage(), palette: [], paletteBands: [])
}

// MARK: - Main image processor coordinator

actor ImageProcessor {

    func process(
        image: UIImage,
        mode: RefPlaneMode,
        valueConfig: ValueConfig,
        colorConfig: ColorConfig,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ProcessingResult {
        onProgress(0.1)
        try Task.checkCancellation()

        let start = CFAbsoluteTimeGetCurrent()
        print("[ImageProcessor] Processing mode=\(mode) image=\(image.size.width)×\(image.size.height)")

        switch mode {
        case .original:
            return ProcessingResult(image: image, palette: [], paletteBands: [])

        case .tonal:
            onProgress(0.3)
            try Task.checkCancellation()
            guard let gray = GrayscaleProcessor.process(image: image) else {
                throw ProcessingError.conversionFailed
            }
            let tonalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Tonal total: \(String(format: "%.1f", tonalMs)) ms")
            onProgress(1.0)
            return ProcessingResult(image: gray, palette: [], paletteBands: [])

        case .value:
            onProgress(0.2)
            try Task.checkCancellation()
            guard let result = ValueStudyProcessor.process(image: image, config: valueConfig) else {
                throw ProcessingError.conversionFailed
            }
            let valueMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Value total: \(String(format: "%.1f", valueMs)) ms")
            onProgress(1.0)
            let palette = result.levelColors.map { uiColor -> Color in Color(uiColor) }
            let bands   = (0..<palette.count).map { $0 }
            return ProcessingResult(image: result.image, palette: palette, paletteBands: bands)

        case .color:
            onProgress(0.2)
            try Task.checkCancellation()
            guard let result = ColorRegionsProcessor.process(image: image, config: colorConfig) else {
                throw ProcessingError.conversionFailed
            }
            let colorMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Color total: \(String(format: "%.1f", colorMs)) ms")
            onProgress(1.0)
            return ProcessingResult(image: result.image, palette: result.palette,
                                    paletteBands: result.paletteBands)
        }
    }
}

// MARK: -

enum ProcessingError: LocalizedError {
    case conversionFailed
    var errorDescription: String? {
        switch self {
        case .conversionFailed: return "Image processing failed. Please try a different image."
        }
    }
}
