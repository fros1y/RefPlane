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
    state.activeMode = .original

    let exported = state.exportCurrentImage()

    #expect(exported?.size == fullResolution.size)
}

@MainActor
@Test
func exportedImagePreservesSourceMetadataAndWritesRefPlaneProvenance() throws {
    let sourceImage = TestImageFactory.makeSolid(width: 120, height: 80, color: .blue)
    let sourceMetadata = SourceImageMetadata(
        properties: [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFArtist as String: "Studio Source"
            ],
            kCGImagePropertyPNGDictionary as String: [
                kCGImagePropertyPNGComment as String: "Camera metadata"
            ]
        ],
        uniformTypeIdentifier: UTType.png.identifier
    )
    let state = AppState()

    state.loadImage(ImportedImagePayload(image: sourceImage, metadata: sourceMetadata))
    state.valueConfig.grayscaleConversion = .luminance
    state.valueConfig.levels = 5
    state.valueConfig.quantizationBias = -0.3
    state.colorConfig.paletteSelectionEnabled = true
    state.colorConfig.numShades = 8
    state.activeMode = .value
    state.paletteColors = [
        Color(red: 0.2, green: 0.3, blue: 0.4),
        Color(red: 0.8, green: 0.7, blue: 0.2)
    ]
    state.pigmentRecipes = [
        PigmentRecipe(
            components: [
                RecipeComponent(
                    pigmentId: "ultramarine_blue",
                    pigmentName: "Ultramarine Blue",
                    concentration: 1
                )
            ],
            predictedColor: OklabColor(L: 0.35, a: -0.02, b: -0.12),
            deltaE: 0.03
        ),
        PigmentRecipe(
            components: [
                RecipeComponent(
                    pigmentId: "cadmium_yellow_light",
                    pigmentName: "Cadmium Yellow Light",
                    concentration: 0.75
                ),
                RecipeComponent(
                    pigmentId: "titanium_white",
                    pigmentName: "Titanium White",
                    concentration: 0.25
                )
            ],
            predictedColor: OklabColor(L: 0.84, a: 0.0, b: 0.11),
            deltaE: 0.04
        )
    ]
    state.clippedRecipeIndices = [1]

    let exportPayload = try #require(state.exportCurrentImagePayload())
    let properties = try exportedMetadata(from: exportPayload.imageData)
    let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let png = properties[kCGImagePropertyPNGDictionary as String] as? [String: Any]

    #expect(exportPayload.contentType == .png)
    #expect(tiff?[kCGImagePropertyTIFFArtist as String] as? String == "Studio Source")

    let provenance = try #require(
        png?[kCGImagePropertyPNGDescription as String] as? String
            ?? tiff?[kCGImagePropertyTIFFImageDescription as String] as? String
            ?? exif?[kCGImagePropertyExifUserComment as String] as? String
    )
    #expect(provenance.contains("\"mode\":\"value\""))
    #expect(provenance.contains("\"gitRevision\""))
    #expect(provenance.contains("\"grayscaleConversion\":\"Luminance\""))
    #expect(provenance.contains("\"valueLevels\":5"))
    #expect(provenance.contains("\"paletteSelectionEnabled\":true"))
    #expect(provenance.contains("\"generatedPalette\""))
    #expect(provenance.contains("\"color\":\"#334C66FF\""))
    #expect(provenance.contains("\"pigmentID\":\"cadmium_yellow_light\""))
    #expect(provenance.contains("\"clipped\":true"))
    #expect(provenance.contains("\"Camera metadata\""))
}

@MainActor
@Test
func currentSettingsDescriptionIncludesAllPipelineSectionsAndPigments() {
    let state = AppState()

    state.setMode(.value)
    state.depthConfig.enabled = true
    state.depthConfig.backgroundMode = .blur
    state.abstractionStrength = 0.65
    state.valueConfig.grayscaleConversion = .average
    state.valueConfig.levels = 5
    state.valueConfig.quantizationBias = -0.4
    state.colorConfig.paletteSelectionEnabled = true
    state.colorConfig.numShades = 6
    state.colorConfig.quantizationBias = 0.5
    state.colorConfig.maxPigmentsPerMix = 2
    state.colorConfig.minConcentration = 0.125
    state.colorConfig.enabledPigmentIDs = [
        "cadmium_yellow_light",
        "ultramarine_blue"
    ]
    state.contourConfig.enabled = true
    state.gridConfig.enabled = true
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
