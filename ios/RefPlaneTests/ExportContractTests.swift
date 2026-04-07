import ImageIO
import SwiftUI
import UIKit
import Testing
import UniformTypeIdentifiers
@testable import Underpaint

@MainActor
@Test
func originalModeExportPrefersFullResolutionSource() {
    let fullResolution = TestImageFactory.makeSolid(width: 2400, height: 1200, color: .red)
    let workingCopy = TestImageFactory.makeSolid(width: 1600, height: 800, color: .red)
    let state = AppState()

    state.fullResolutionOriginalImage = fullResolution
    state.originalImage = workingCopy
    state.sourceImage = workingCopy
    state.transform.activeMode = .original

    let exported = state.exportCurrentImage()

    #expect(exported?.size == fullResolution.size)
}

@MainActor
@Test
func exportedImagePayloadAlwaysUsesPNGAndRenderedImageDimensions() throws {
    let sourceImage = TestImageFactory.makeSolid(width: 120, height: 80, color: .blue)
    let processedImage = TestImageFactory.makeSolid(width: 60, height: 30, color: .green)
    let sourceMetadata = SourceImageMetadata(
        properties: [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFArtist as String: "Studio Source"
            ],
            kCGImagePropertyPNGDictionary as String: [
                kCGImagePropertyPNGComment as String: "Camera metadata"
            ]
        ],
        uniformTypeIdentifier: UTType.jpeg.identifier
    )
    let state = AppState()

    state.loadImage(ImportedImagePayload(image: sourceImage, metadata: sourceMetadata))
    state.transform.activeMode = .value
    state.processedImage = processedImage

    let exportPayload = try #require(state.exportCurrentImagePayload())
    let properties = try exportedMetadata(from: exportPayload.imageData)
    let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]
    let pixelSize = try exportedPixelSize(from: exportPayload.imageData)

    #expect(exportPayload.contentType == .png)
    #expect(pixelSize.width == 60)
    #expect(pixelSize.height == 30)
    #expect(tiff == nil)
    #expect(exif == nil)
    #expect(png?[kCGImagePropertyPNGComment as String] as? String == nil)
    #expect(png?[kCGImagePropertyPNGDescription as String] as? String == nil)
}

@MainActor
@Test
func currentSettingsDescriptionIncludesAllPipelineSectionsAndPigments() {
    let state = AppState()

    state.setMode(.value)
    state.depth.depthConfig.enabled = true
    state.depth.depthConfig.backgroundMode = .blur
    state.transform.abstractionStrength = 0.65
    state.transform.valueConfig.grayscaleConversion = .average
    state.transform.valueConfig.levels = 5
    state.transform.valueConfig.quantizationBias = -0.4
    state.transform.colorConfig.paletteSelectionEnabled = true
    state.transform.colorConfig.numShades = 6
    state.transform.colorConfig.quantizationBias = 0.5
    state.transform.colorConfig.maxPigmentsPerMix = 2
    state.transform.colorConfig.minConcentration = 0.125
    state.transform.colorConfig.enabledPigmentIDs = [
        "cadmium_yellow_light",
        "ultramarine_blue"
    ]
    state.transform.contourConfig.enabled = true
    state.transform.gridConfig.enabled = true
    state.paletteColors = [
        Color(red: 0.91, green: 0.82, blue: 0.61),
        Color(red: 0.05, green: 0.05, blue: 0.05)
    ]
    state.pigmentRecipes = [
        PigmentRecipe(
            components: [
                RecipeComponent(
                    pigmentId: "cadmium_yellow_light",
                    pigmentName: "Cadmium Yellow Light",
                    concentration: 0.75
                ),
                RecipeComponent(
                    pigmentId: "ultramarine_blue",
                    pigmentName: "Ultramarine Blue",
                    concentration: 0.25
                )
            ],
            predictedColor: OklabColor(L: 0.8, a: -0.01, b: 0.08),
            deltaE: 0.035
        ),
        PigmentRecipe(
            components: [
                RecipeComponent(
                    pigmentId: "ultramarine_blue",
                    pigmentName: "Ultramarine Blue",
                    concentration: 1
                )
            ],
            predictedColor: OklabColor(L: 0.2, a: -0.01, b: -0.08),
            deltaE: 0.012
        )
    ]
    state.clippedRecipeIndices = [0]

    let summary = state.currentSettingsDescription()

    #expect(summary.contains("Application"))
    #expect(summary.contains("Mode\nValue"))
    #expect(summary.contains("Background"))
    #expect(summary.contains("Simplification"))
    #expect(summary.contains("Grayscale Conversion\nAverage"))
    #expect(summary.contains("Limit Colors / Values"))
    #expect(summary.contains("Palette Selection"))
    #expect(summary.contains("Contours"))
    #expect(summary.contains("Grid"))
    #expect(summary.contains("Cadmium Yellow Light [cadmium_yellow_light]"))
    #expect(summary.contains("Ultramarine Blue [ultramarine_blue]"))
    #expect(summary.contains("Generated Palette"))
    #expect(summary.contains("Swatch 1"))
    #expect(summary.contains("#E8D19CFF"))
    #expect(summary.contains("Cadmium Yellow Light 75% + Ultramarine Blue 25%"))
    #expect(summary.contains("Delta E 0.035"))
    #expect(summary.contains("Clipped"))
}

private func exportedMetadata(from imageData: Data) throws -> [String: Any] {
    let source = try #require(CGImageSourceCreateWithData(imageData as CFData, nil))
    return try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    )
}

private func exportedPixelSize(from imageData: Data) throws -> CGSize {
    let properties = try exportedMetadata(from: imageData)
    let width = try #require(properties[kCGImagePropertyPixelWidth as String] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight as String] as? Int)
    return CGSize(width: width, height: height)
}
