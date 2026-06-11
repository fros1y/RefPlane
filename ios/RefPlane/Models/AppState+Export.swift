import SwiftUI
import os

// MARK: - Export & Formatting

extension AppState {
    func exportCurrentImage() -> UIImage? {
        let base: UIImage?
        if transform.activeMode == .original, let fullResolutionOriginalImage {
            base = fullResolutionOriginalImage
        } else {
            base = currentDisplayImage
        }
        guard let image = base else { return nil }
        var rendered = image
        if transform.gridConfig.enabled {
            rendered = renderGridOnto(rendered)
        }
        if transform.contourConfig.enabled && !depth.contourSegments.isEmpty {
            rendered = renderContoursOnto(rendered)
        }
        return rendered
    }

    func exportCurrentImagePayload() -> ExportedImagePayload? {
        guard let image = exportCurrentImage() else { return nil }
        guard let imageData = image.pngData() else { return nil }
        return ExportedImagePayload(image: image, imageData: imageData, contentType: .png)
    }

    /// Compose the Prep Sheet: reference + value study + color study + recipes
    /// on a single print-ready page. Value and color renders are re-processed
    /// on demand from the current source (no caching — export is infrequent).
    func exportPrepSheet(format: PrepSheetFormat) async throws -> ExportedDocumentPayload {
        guard let source = displayBaseImage else {
            throw PrepSheetError.noImageLoaded
        }

        pipeline.isProcessing = true
        pipeline.processingLabel = "Composing Prep Sheet…"
        pipeline.processingIsIndeterminate = false
        pipeline.processingProgress = 0
        pipeline.errorMessage = nil
        defer {
            pipeline.isProcessing = false
            pipeline.processingLabel = "Processing…"
            pipeline.processingProgress = 0
        }

        // The value panel always needs a concrete grayscale conversion, even
        // when the user is currently in a color-bearing mode.
        var valueConfig = transform.valueConfig
        if valueConfig.grayscaleConversion == .none {
            valueConfig.grayscaleConversion = .luminance
        }
        let colorConfig = transform.colorConfig

        let valueResult = try await processOperation(source, .value, valueConfig, colorConfig) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.pipeline.processingProgress = progress * 0.4
            }
        }
        try Task.checkCancellation()

        let colorResult = try await processOperation(source, .color, valueConfig, colorConfig) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.pipeline.processingProgress = 0.4 + progress * 0.4
            }
        }
        try Task.checkCancellation()

        var referenceImage = source
        if transform.gridConfig.enabled {
            referenceImage = renderGridOnto(referenceImage)
        }

        var valueImage = valueResult.image
        var colorImage = colorResult.image
        if depth.depthConfig.enabled, let depthMapImage = depth.depthMap {
            let depthConfig = depth.depthConfig
            valueImage = depthEffectOperation(valueImage, depthMapImage, depthConfig) ?? valueImage
            colorImage = depthEffectOperation(colorImage, depthMapImage, depthConfig) ?? colorImage
        }

        pipeline.processingProgress = 0.85

        let content = PrepSheetContent(
            referenceImage: referenceImage,
            valueImage: valueImage,
            colorImage: colorImage,
            paletteColors: colorResult.palette,
            pigmentRecipes: colorResult.pigmentRecipes,
            valueLevels: valueConfig.levels,
            valueDistributionName: valueConfig.distribution.rawValue,
            colorCount: colorConfig.numShades,
            usesPigments: colorConfig.paletteSelectionEnabled
        )

        let data = try PrepSheetRenderer.render(content, format: format)
        pipeline.processingProgress = 1

        return ExportedDocumentPayload(
            data: data,
            contentType: format.contentType,
            filename: "underpaint-kit-\(Self.prepSheetDateStamp(for: Date())).\(format.fileExtension)"
        )
    }

    static func prepSheetDateStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    func currentSettingsDescription() -> String {
        let settings = makeExportSettingsSnapshot()
        let pigmentSummary = selectedPigmentDescription(
            for: settings.enabledPigmentIDs
        )
        let generatedPalette = makeGeneratedPaletteSnapshot()

        var lines = [
            "Application",
            makeExportSoftwareDescription(),
            "",
            "Mode",
            transform.activeMode.label,
            "",
            "Background",
            "Enabled: \(displayDescription(for: settings.backgroundProcessingEnabled))",
            "Mode: \(settings.backgroundMode)",
            "Foreground Cutoff: \(formattedScalar(settings.foregroundDepthCutoff))",
            "Background Cutoff: \(formattedScalar(settings.backgroundDepthCutoff))",
            "Intensity: \(formattedScalar(settings.depthEffectIntensity))",
            "",
            "Simplification",
            "Method: \(settings.abstractionMethod)",
            "Strength: \(formattedScalar(settings.abstractionStrength))",
            "",
            "Grayscale Conversion",
            settings.grayscaleConversion,
            "",
            "Limit Colors / Values",
            "Values: \(settings.valueLevels)",
            "Value Bias: \(QuantizationBias.displayName(for: settings.valueQuantizationBias)) (\(formattedSignedScalar(settings.valueQuantizationBias)))",
            "Colors: \(settings.colorLimit)",
            "Color Bias: \(QuantizationBias.displayName(for: settings.colorQuantizationBias)) (\(formattedSignedScalar(settings.colorQuantizationBias)))",
            "",
            "Palette Selection",
            "Enabled: \(displayDescription(for: settings.paletteSelectionEnabled))",
            "Spread: \(formattedSignedScalar(settings.paletteSpread))",
            "Max Pigments per Mix: \(settings.maxPigmentsPerMix)",
            "Min Concentration: \(formattedScalar(Double(settings.minConcentration)))",
            "Pigments (\(settings.enabledPigmentIDs.count)): \(pigmentSummary)",
            "",
            "Contours",
            "Enabled: \(displayDescription(for: settings.contourEnabled))",
            "Levels: \(settings.contourLevels)",
            "Line Style: \(settings.contourLineStyle)",
            "Color: \(settings.contourCustomColor)",
            "Opacity: \(formattedScalar(settings.contourOpacity))",
            "",
            "Grid",
            "Enabled: \(displayDescription(for: settings.gridEnabled))",
            "Divisions: \(settings.gridDivisions)",
            "Diagonals: \(displayDescription(for: settings.gridShowDiagonals))",
            "Line Style: \(settings.gridLineStyle)",
            "Color: \(settings.gridCustomColor)",
            "Opacity: \(formattedScalar(settings.gridOpacity))"
        ]

        if !generatedPalette.isEmpty {
            lines.append("")
            lines.append("Generated Palette")
            lines.append(contentsOf: generatedPaletteDescription(from: generatedPalette))
        }

        return lines.joined(separator: "\n")
    }

    func makeExportSoftwareDescription() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let gitRevision = makeExportGitRevision()
        return "Underpaint \(version) (\(build), git \(gitRevision))"
    }

    func makeExportGitRevision() -> String {
        if let revision = Bundle.main.object(forInfoDictionaryKey: "RefPlaneGitRevision") as? String,
           !revision.isEmpty {
            return revision
        }

        guard let url = Bundle.main.url(
            forResource: "RefPlaneBuildMetadata",
            withExtension: "plist"
        ),
        let metadata = NSDictionary(contentsOf: url) as? [String: Any],
        let revision = metadata["gitRevision"] as? String,
        !revision.isEmpty
        else {
            return "unknown"
        }

        return revision
    }

    func makeExportSettingsSnapshot() -> ExportSettingsMetadata {
        ExportSettingsMetadata(
            abstractionStrength: transform.abstractionStrength,
            abstractionMethod: transform.abstractionMethod.rawValue,
            grayscaleConversion: transform.valueConfig.grayscaleConversion.rawValue,
            valueLevels: transform.valueConfig.levels,
            valueQuantizationBias: transform.valueConfig.quantizationBias,
            paletteSelectionEnabled: transform.colorConfig.paletteSelectionEnabled,
            colorLimit: transform.colorConfig.numShades,
            colorQuantizationBias: transform.colorConfig.quantizationBias,
            paletteSpread: transform.colorConfig.paletteSpread,
            maxPigmentsPerMix: transform.colorConfig.maxPigmentsPerMix,
            minConcentration: transform.colorConfig.minConcentration,
            enabledPigmentIDs: transform.colorConfig.enabledPigmentIDs.sorted(),
            backgroundProcessingEnabled: depth.depthConfig.enabled,
            backgroundMode: depth.depthConfig.backgroundMode.rawValue,
            foregroundDepthCutoff: depth.depthConfig.foregroundCutoff,
            backgroundDepthCutoff: depth.depthConfig.backgroundCutoff,
            depthEffectIntensity: depth.depthConfig.effectIntensity,
            gridEnabled: transform.gridConfig.enabled,
            gridDivisions: transform.gridConfig.divisions,
            gridShowDiagonals: transform.gridConfig.showDiagonals,
            gridLineStyle: transform.gridConfig.lineStyle.rawValue,
            gridCustomColor: metadataDescription(for: transform.gridConfig.customColor),
            gridOpacity: transform.gridConfig.opacity,
            contourEnabled: transform.contourConfig.enabled,
            contourLevels: transform.contourConfig.levels,
            contourLineStyle: transform.contourConfig.lineStyle.rawValue,
            contourCustomColor: metadataDescription(for: transform.contourConfig.customColor),
            contourOpacity: transform.contourConfig.opacity
        )
    }

    func metadataDescription(for color: Color) -> String {
        let resolvedColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return resolvedColor.description
        }

        return String(
            format: "#%02X%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()),
            Int((alpha * 255).rounded())
        )
    }

    func selectedPigmentDescription(for pigmentIDs: [String]) -> String {
        let namesByID = Dictionary(
            uniqueKeysWithValues: SpectralDataStore.essentialPigments.map {
                ($0.id, $0.name)
            }
        )

        return pigmentIDs
            .map { pigmentID in
                if let name = namesByID[pigmentID] {
                    return "\(name) [\(pigmentID)]"
                }
                return pigmentID
            }
            .joined(separator: ", ")
    }

    func makeGeneratedPaletteSnapshot() -> [ExportGeneratedPaletteMetadata] {
        guard !paletteColors.isEmpty else { return [] }

        var pixelCounts = [Int](repeating: 0, count: paletteColors.count)
        for band in processedPixelBands where pixelCounts.indices.contains(band) {
            pixelCounts[band] += 1
        }
        let totalPixels = max(1, pixelCounts.reduce(0, +))
        let clippedIndices = Set(clippedRecipeIndices)

        return paletteColors.indices.map { index in
            let recipe = pigmentRecipes.flatMap { recipes in
                recipes.indices.contains(index) ? recipes[index] : nil
            }

            return ExportGeneratedPaletteMetadata(
                index: index,
                color: metadataDescription(for: paletteColors[index]),
                pixelCount: pixelCounts[index],
                pixelShare: Double(pixelCounts[index]) / Double(totalPixels),
                recipe: recipe.map { exportGeneratedRecipeMetadata(from: $0) },
                clipped: clippedIndices.contains(index)
            )
        }
    }

    func exportGeneratedRecipeMetadata(
        from recipe: PigmentRecipe
    ) -> ExportGeneratedRecipeMetadata {
        ExportGeneratedRecipeMetadata(
            deltaE: recipe.deltaE,
            components: recipe.components.map { component in
                ExportGeneratedRecipeComponentMetadata(
                    pigmentID: component.pigmentId,
                    pigmentName: component.pigmentName,
                    concentration: component.concentration
                )
            }
        )
    }

    func generatedPaletteDescription(
        from entries: [ExportGeneratedPaletteMetadata]
    ) -> [String] {
        entries.map { entry in
            var parts = [
                "Swatch \(entry.index + 1)",
                entry.color,
                "\(formattedScalar(entry.pixelShare * 100))% (\(entry.pixelCount) px)"
            ]

            if let recipe = entry.recipe {
                let mix = recipe.components
                    .map { component in
                        "\(component.pigmentName) \(formattedScalar(Double(component.concentration * 100)))%"
                    }
                    .joined(separator: " + ")
                parts.append(mix)
                parts.append("Delta E \(formattedScalar(Double(recipe.deltaE)))")
                if entry.clipped {
                    parts.append("Clipped")
                }
            }

            return parts.joined(separator: " | ")
        }
    }

    func displayDescription(for isEnabled: Bool) -> String {
        isEnabled ? "On" : "Off"
    }

    func formattedScalar(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    func formattedSignedScalar(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...3))
                .sign(strategy: .always(includingZero: false))
        )
    }

    func renderGridOnto(_ image: UIImage) -> UIImage {
        let size = image.size
        let config = transform.gridConfig
        let lineWidth = max(1.0, min(size.width, size.height) / 1000.0)
        let segments = GridLineColorResolver.resolvedSegments(
            config: config,
            image: image,
            segments: GridLineColorResolver.normalizedSegments(
                config: config,
                imageSize: size
            )
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.square)
            cg.clip(to: CGRect(origin: .zero, size: size))

            for resolvedSegment in segments {
                let mappedSegment = resolvedSegment.segment.mapped(
                    to: CGRect(origin: .zero, size: size)
                )
                let color = UIColor(resolvedSegment.color).withAlphaComponent(config.opacity)
                cg.setStrokeColor(color.cgColor)
                cg.move(to: mappedSegment.start)
                cg.addLine(to: mappedSegment.end)
                cg.strokePath()
            }
        }
    }

struct ExportSettingsMetadata: Encodable {
    var abstractionStrength: Double
    var abstractionMethod: String
    var grayscaleConversion: String
    var valueLevels: Int
    var valueQuantizationBias: Double
    var paletteSelectionEnabled: Bool
    var colorLimit: Int
    var colorQuantizationBias: Double
    var paletteSpread: Double
    var maxPigmentsPerMix: Int
    var minConcentration: Float
    var enabledPigmentIDs: [String]
    var backgroundProcessingEnabled: Bool
    var backgroundMode: String
    var foregroundDepthCutoff: Double
    var backgroundDepthCutoff: Double
    var depthEffectIntensity: Double
    var gridEnabled: Bool
    var gridDivisions: Int
    var gridShowDiagonals: Bool
    var gridLineStyle: String
    var gridCustomColor: String
    var gridOpacity: Double
    var contourEnabled: Bool
    var contourLevels: Int
    var contourLineStyle: String
    var contourCustomColor: String
    var contourOpacity: Double
}

struct ExportGeneratedPaletteMetadata: Encodable {
    var index: Int
    var color: String
    var pixelCount: Int
    var pixelShare: Double
    var recipe: ExportGeneratedRecipeMetadata?
    var clipped: Bool
}

struct ExportGeneratedRecipeMetadata: Encodable {
    var deltaE: Float
    var components: [ExportGeneratedRecipeComponentMetadata]
}

struct ExportGeneratedRecipeComponentMetadata: Encodable {
    var pigmentID: String
    var pigmentName: String
    var concentration: Float
}
}
