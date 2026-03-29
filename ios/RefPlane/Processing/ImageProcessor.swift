import UIKit
import SwiftUI

// MARK: - Processing result

struct ProcessingResult {
    let image: UIImage
    let palette: [Color]
    let paletteBands: [Int]
    let pixelBands: [Int]
    let pigmentRecipes: [PigmentRecipe]?

    static let empty = ProcessingResult(image: UIImage(), palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil)
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
            return ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil)

        case .tonal:
            onProgress(0.3)
            try Task.checkCancellation()
            guard let gray = GrayscaleProcessor.process(image: image) else {
                throw ProcessingError.conversionFailed
            }
            let tonalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Tonal total: \(String(format: "%.1f", tonalMs)) ms")
            onProgress(1.0)
            return ProcessingResult(image: gray, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil)

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
            return ProcessingResult(
                image: result.image,
                palette: palette,
                paletteBands: bands,
                pixelBands: result.pixelBands,
                pigmentRecipes: nil
            )

        case .color:
            onProgress(0.2)
            try Task.checkCancellation()
            guard let result = ColorRegionsProcessor.process(image: image, config: colorConfig) else {
                throw ProcessingError.conversionFailed
            }
            let colorMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Color total: \(String(format: "%.1f", colorMs)) ms")

            var pigmentRecipes: [PigmentRecipe]? = nil
            var outputImage = result.image
            if colorConfig.paintMixEnabled {
                onProgress(0.85)
                try Task.checkCancellation()
                let db = SpectralDataStore.shared
                let pigments = SpectralDataStore.essentialPigments
                let mixStart = CFAbsoluteTimeGetCurrent()
                pigmentRecipes = PigmentDecomposer.decompose(
                    targetColors: result.quantizedCentroids,
                    pigments: pigments,
                    database: db,
                    maxPigments: colorConfig.maxPigmentsPerMix
                )
                let mixMs = (CFAbsoluteTimeGetCurrent() - mixStart) * 1000
                print("[ImageProcessor] PigmentDecomposer: \(String(format: "%.1f", mixMs)) ms for \(result.quantizedCentroids.count) colors")

                if let recipes = pigmentRecipes,
                   let (existingPixels, w, h) = result.image.toPixelData() {
                    let labels = result.pixelLabels
                    var remapped = existingPixels
                    for i in 0..<w * h {
                        let label = min(max(Int(labels[i]), 0), recipes.count - 1)
                        let (r, g, b) = oklabToRGB(recipes[label].predictedColor)
                        let base = i * 4
                        remapped[base]     = r
                        remapped[base + 1] = g
                        remapped[base + 2] = b
                    }
                    if let img = UIImage.fromPixelData(remapped, width: w, height: h) {
                        outputImage = img
                    }
                }
            }

            let outputPalette: [Color]
            if let recipes = pigmentRecipes {
                outputPalette = recipes.map { recipe in
                    let (r, g, b) = oklabToRGB(recipe.predictedColor)
                    return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
                }
            } else {
                outputPalette = result.palette
            }

            onProgress(1.0)
            return ProcessingResult(
                image: outputImage,
                palette: outputPalette,
                paletteBands: result.paletteBands,
                pixelBands: result.pixelBands,
                pigmentRecipes: pigmentRecipes
            )
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
