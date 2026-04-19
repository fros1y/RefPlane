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

    func exportPrepSheetPayload(format: PrepSheetExportFormat) async throws -> ExportedFilePayload {
        guard let source = displayBaseImage else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let token = processing.start(
            for: .prepSheet(format),
            label: "Rendering painter's kit…"
        )
        defer {
            processing.finish(token: token)
        }

        let referenceImage = transform.gridConfig.enabled ? renderGridOnto(source) : source

        processing.updateLabel("Generating value study…", token: token)
        processing.updateProgress(0.12, token: token)
        let valueResult = try await renderPrepSheetResult(
            source: source,
            mode: .value,
            progressRange: 0.12...0.44,
            token: token
        )
        let valueImage = renderPrepSheetPanelImage(from: valueResult.image)

        processing.updateLabel("Generating color study…", token: token)
        processing.updateProgress(0.46, token: token)
        let colorResult = try await renderPrepSheetResult(
            source: source,
            mode: .color,
            progressRange: 0.46...0.78,
            token: token
        )
        let colorImage = renderPrepSheetPanelImage(from: colorResult.image)

        processing.updateLabel("Composing painter's kit…", token: token)
        processing.updateProgress(0.82, token: token)

        let sheetImage = PrepSheetRenderer.renderSheetImage(
            content: PrepSheetContent(
                title: currentReferenceName,
                date: Date.now.formatted(date: .abbreviated, time: .omitted),
                referenceImage: referenceImage,
                valueImage: valueImage,
                colorImage: colorImage,
                softwareDescription: makeExportSoftwareDescription(),
                paletteEntries: makePrepSheetPaletteEntries(from: colorResult)
            )
        )

        let data: Data
        switch format {
        case .png:
            guard let pngData = sheetImage.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            data = pngData
        case .pdf:
            data = PrepSheetRenderer.renderPDFData(from: sheetImage)
        }

        processing.updateProgress(1, token: token)

        return ExportedFilePayload(
            data: data,
            contentType: format.contentType,
            defaultFilename: prepSheetFilenameStem
        )
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

    private func renderPrepSheetResult(
        source: UIImage,
        mode: RefPlaneMode,
        progressRange: ClosedRange<Double>,
        token: UUID
    ) async throws -> ProcessingResult {
        try await processOperation(
            source,
            mode,
            transform.valueConfig,
            transform.colorConfig
        ) { [weak self] progress in
            Task { @MainActor [weak self] in
                let mapped = progressRange.lowerBound
                    + (progressRange.upperBound - progressRange.lowerBound) * progress
                self?.processing.updateProgress(mapped, token: token)
            }
        }
    }

    private func renderPrepSheetPanelImage(from processed: UIImage) -> UIImage {
        var output = processed

        if depth.depthConfig.enabled, let depthMap = depth.depthMap {
            output = depthEffectOperation(processed, depthMap, depth.depthConfig) ?? output
        }

        if transform.contourConfig.enabled && !depth.contourSegments.isEmpty {
            output = renderContoursOnto(output)
        }

        return output
    }

    private func makePrepSheetPaletteEntries(from result: ProcessingResult) -> [PrepSheetPaletteEntry] {
        guard !result.palette.isEmpty else { return [] }

        return result.palette.indices.map { index in
            let color = result.palette[index]
            let recipe = result.pigmentRecipes.flatMap { recipes in
                recipes.indices.contains(index) ? recipes[index] : nil
            }
            let title = PaletteColorNamer.name(for: color) ?? "Swatch \(index + 1)"

            let mixSummary = recipe.map { recipe in
                recipe.components
                    .map { component in
                        "\(component.pigmentName) \(Int((component.concentration * 10).rounded()))"
                    }
                    .joined(separator: " · ")
            } ?? "Simplified color area"

            return PrepSheetPaletteEntry(
                id: index,
                title: title,
                color: color,
                mixSummary: mixSummary
            )
        }
    }

    private var prepSheetFilenameStem: String {
        let safeName = currentReferenceName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let name = safeName.isEmpty ? "reference" : safeName
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        return "underpaint-kit-\(name)-\(stamp)"
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

private struct PrepSheetContent {
    let title: String
    let date: String
    let referenceImage: UIImage
    let valueImage: UIImage
    let colorImage: UIImage
    let softwareDescription: String
    let paletteEntries: [PrepSheetPaletteEntry]
}

private struct PrepSheetPaletteEntry: Identifiable {
    let id: Int
    let title: String
    let color: Color
    let mixSummary: String
}

private enum PrepSheetRenderer {
    static let pageSize = CGSize(width: 1650, height: 1275)

    @MainActor
    static func renderSheetImage(content: PrepSheetContent) -> UIImage {
        let renderer = ImageRenderer(
            content: PrepSheetLayoutView(content: content)
                .frame(width: pageSize.width, height: pageSize.height)
        )
        renderer.proposedSize = ProposedViewSize(pageSize)
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }

    static func renderPDFData(from image: UIImage) -> Data {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            image.draw(in: bounds)
        }
    }
}

private struct PrepSheetLayoutView: View {
    let content: PrepSheetContent

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.95, blue: 0.92)

            VStack(spacing: 24) {
                header

                HStack(alignment: .top, spacing: 20) {
                    panel(title: "Reference", subtitle: "Grid", image: content.referenceImage)
                    panel(title: "Value Study", subtitle: "Banded", image: content.valueImage)
                }

                HStack(alignment: .top, spacing: 20) {
                    panel(title: "Color Study", subtitle: "Palette", image: content.colorImage)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    palettePanel
                        .frame(width: 470)
                }

                footer
            }
            .padding(34)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("UNDERPAINT")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .tracking(1.2)
                Text(content.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }

            Spacer()

            Text(content.date)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func panel(title: String, subtitle: String, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var palettePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Palette + Recipes")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(content.paletteEntries.prefix(8)) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle().stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(entry.mixSummary)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(height: 492)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Text(content.softwareDescription)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Text("Painter's Kit")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }
}
