import ImageIO
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
    #expect(provenance.contains("\"Camera metadata\""))
}

private func exportedMetadata(from imageData: Data) throws -> [String: Any] {
    let source = try #require(CGImageSourceCreateWithData(imageData as CFData, nil))
    return try #require(
        CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    )
}
