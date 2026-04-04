import UIKit
import SwiftUI

// MARK: - Processing result

struct ProcessingResult {
    let image: UIImage
    let palette: [Color]
    let paletteBands: [Int]
    let pixelBands: [Int]
    let pigmentRecipes: [PigmentRecipe]?
    let selectedTubes: [PigmentData]
    let clippedRecipeIndices: [Int]

    static let empty = ProcessingResult(
        image: UIImage(),
        palette: [],
        paletteBands: [],
        pixelBands: [],
        pigmentRecipes: nil,
        selectedTubes: [],
        clippedRecipeIndices: []
    )
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
            return ProcessingResult(image: image, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])

        case .tonal:
            onProgress(0.3)
            try Task.checkCancellation()
            guard let gray = GrayscaleProcessor.process(
                image: image,
                conversion: valueConfig.grayscaleConversion
            ) else {
                throw ProcessingError.conversionFailed
            }
            let tonalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Tonal total: \(String(format: "%.1f", tonalMs)) ms")
            onProgress(1.0)
            return ProcessingResult(image: gray, palette: [], paletteBands: [], pixelBands: [], pigmentRecipes: nil, selectedTubes: [], clippedRecipeIndices: [])

        case .value:
            onProgress(0.2)
            try Task.checkCancellation()
            guard let valueResult = ValueStudyProcessor.process(image: image, config: valueConfig) else {
                throw ProcessingError.conversionFailed
            }
            let valueMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Value total: \(String(format: "%.1f", valueMs)) ms")

            let baseResult = makeBaseProcessingResult(
                image: valueResult.image,
                palette: valueResult.levelColors.map { Color($0) },
                pixelBands: valueResult.pixelBands
            )

            guard colorConfig.paletteSelectionEnabled else {
                onProgress(1.0)
                return baseResult
            }

            let colorRegions = makeColorRegions(from: valueResult)
            let paletteResult = try await applyPaletteSelection(
                to: colorRegions,
                baseResult: baseResult,
                config: grayscalePaletteConfig(from: colorConfig, levels: valueResult.levelColors.count),
                onProgress: onProgress
            )
            onProgress(1.0)
            return paletteResult

        case .color:
            onProgress(0.05)
            try Task.checkCancellation()
            let overclusterK = colorConfig.paletteSelectionEnabled
                ? min(2 * max(2, colorConfig.numShades), 48)
                : nil
            guard let result = ColorRegionsProcessor.process(image: image, config: colorConfig, overclusterK: overclusterK) else {
                throw ProcessingError.conversionFailed
            }
            let colorMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[ImageProcessor] Color total: \(String(format: "%.1f", colorMs)) ms")

            let baseResult = ProcessingResult(
                image: result.image,
                palette: result.palette,
                paletteBands: result.paletteBands,
                pixelBands: result.pixelBands,
                pigmentRecipes: nil,
                selectedTubes: [],
                clippedRecipeIndices: []
            )

            guard colorConfig.paletteSelectionEnabled else {
                onProgress(1.0)
                return baseResult
            }

            let paletteResult = try await applyPaletteSelection(
                to: result,
                baseResult: baseResult,
                config: colorConfig,
                onProgress: onProgress
            )
            onProgress(1.0)
            return paletteResult
        }
    }
}

private extension ImageProcessor {
    func makeBaseProcessingResult(
        image: UIImage,
        palette: [Color],
        pixelBands: [Int]
    ) -> ProcessingResult {
        ProcessingResult(
            image: image,
            palette: palette,
            paletteBands: (0..<palette.count).map { $0 },
            pixelBands: pixelBands,
            pigmentRecipes: nil,
            selectedTubes: [],
            clippedRecipeIndices: []
        )
    }

    func applyPaletteSelection(
        to colorRegions: ColorRegionsProcessor.Result,
        baseResult: ProcessingResult,
        config: ColorConfig,
        onProgress: @escaping (Double) -> Void
    ) async throws -> ProcessingResult {
        onProgress(0.2)
        try Task.checkCancellation()

        let db = SpectralDataStore.shared
        let allPigments = SpectralDataStore.essentialPigments
        let pigments = allPigments.filter { config.enabledPigmentIDs.contains($0.id) }

        do {
            let pb = try PaintPaletteBuilder.build(
                colorRegions: colorRegions,
                config: config,
                database: db,
                pigments: pigments,
                onProgress: onProgress
            )

            let outputPalette = pb.recipes.map { recipe in
                let (r, g, b) = oklabToRGB(recipe.predictedColor)
                return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
            }
            let outputImage = remapImage(
                baseImage: colorRegions.image,
                recipes: pb.recipes,
                pixelLabels: pb.pixelLabels
            ) ?? colorRegions.image

            return ProcessingResult(
                image: outputImage,
                palette: outputPalette,
                paletteBands: (0..<outputPalette.count).map { $0 },
                pixelBands: pb.pixelLabels.map { Int($0) },
                pigmentRecipes: pb.recipes,
                selectedTubes: pb.selectedTubes,
                clippedRecipeIndices: pb.clippedRecipeIndices
            )
        } catch {
            print("[ImageProcessor] Palette selection failed, using quantized base image: \(error)")
            return baseResult
        }
    }

    func makeColorRegions(
        from valueResult: ValueStudyProcessor.Result
    ) -> ColorRegionsProcessor.Result {
        let quantizedCentroids = valueResult.levelColors.map { color in
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return rgbToOklab(
                r: UInt8((red * 255).rounded()),
                g: UInt8((green * 255).rounded()),
                b: UInt8((blue * 255).rounded())
            )
        }

        var clusterPixelCounts = [Int](repeating: 0, count: quantizedCentroids.count)
        let pixelLabels = valueResult.pixelBands.map { band -> Int32 in
            let clampedBand = min(max(band, 0), max(quantizedCentroids.count - 1, 0))
            clusterPixelCounts[clampedBand] += 1
            return Int32(clampedBand)
        }

        return ColorRegionsProcessor.Result(
            image: valueResult.image,
            palette: valueResult.levelColors.map { Color($0) },
            paletteBands: (0..<valueResult.levelColors.count).map { $0 },
            pixelBands: valueResult.pixelBands,
            quantizedCentroids: quantizedCentroids,
            pixelLabels: pixelLabels,
            pixelLab: [],
            clusterPixelCounts: clusterPixelCounts,
            clusterSalience: Array(repeating: 1, count: quantizedCentroids.count)
        )
    }

    func grayscalePaletteConfig(from colorConfig: ColorConfig, levels: Int) -> ColorConfig {
        var config = colorConfig
        config.numShades = max(2, levels)
        return config
    }

    func remapImage(
        baseImage: UIImage,
        recipes: [PigmentRecipe],
        pixelLabels: [Int32]
    ) -> UIImage? {
        guard !recipes.isEmpty,
              let (existingPixels, width, height) = baseImage.toPixelData()
        else {
            return nil
        }

        let pixelCount = width * height
        guard pixelLabels.count == pixelCount else { return nil }

        var remapped = existingPixels
        for index in 0..<pixelCount {
            let label = min(max(Int(pixelLabels[index]), 0), recipes.count - 1)
            let (r, g, b) = oklabToRGB(recipes[label].predictedColor)
            let base = index * 4
            remapped[base] = r
            remapped[base + 1] = g
            remapped[base + 2] = b
        }

        return UIImage.fromPixelData(remapped, width: width, height: height)
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
