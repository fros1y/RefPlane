import Testing
import SwiftUI
import UIKit
import UniformTypeIdentifiers
@testable import Underpaint

// MARK: - Fixtures

@MainActor
private func makeContent(
    usesPigments: Bool = true,
    recipeCount: Int = 3,
    paletteCount: Int = 3
) -> PrepSheetContent {
    let palette = (0..<paletteCount).map { index in
        Color(white: Double(index) / Double(max(1, paletteCount - 1)))
    }

    let recipes: [PigmentRecipe]? = usesPigments
        ? (0..<recipeCount).map { index in
            PigmentRecipe(
                components: [
                    RecipeComponent(
                        pigmentId: "pigment-a-\(index)",
                        pigmentName: "Pigment A\(index)",
                        concentration: 0.75
                    ),
                    RecipeComponent(
                        pigmentId: "pigment-b-\(index)",
                        pigmentName: "Pigment B\(index)",
                        concentration: 0.25
                    ),
                ],
                predictedColor: OklabColor(L: 0.5, a: 0, b: 0),
                deltaE: 1.0
            )
        }
        : nil

    return PrepSheetContent(
        referenceImage: TestImageFactory.makeSolid(width: 64, height: 48, color: .brown),
        valueImage: TestImageFactory.makeSolid(width: 64, height: 48, color: .gray),
        colorImage: TestImageFactory.makeSolid(width: 64, height: 48, color: .orange),
        paletteColors: palette,
        pigmentRecipes: recipes,
        valueLevels: 5,
        valueDistributionName: "Shadow Detail",
        colorCount: paletteCount,
        usesPigments: usesPigments
    )
}

// MARK: - Format metadata

@Test
func prepSheetFormatsDeclareMatchingContentTypes() {
    #expect(PrepSheetFormat.pdf.contentType == .pdf)
    #expect(PrepSheetFormat.png.contentType == .png)
    #expect(PrepSheetFormat.pdf.fileExtension == "pdf")
    #expect(PrepSheetFormat.png.fileExtension == "png")
}

@Test
func prepSheetPageSizesMatchPaperStandards() {
    #expect(PrepSheetPageSize.usLetter.pointSize == CGSize(width: 612, height: 792))
    #expect(PrepSheetPageSize.a4.pointSize == CGSize(width: 595, height: 842))
}

// MARK: - PDF rendering

@MainActor
@Test
func pdfRenderProducesValidSinglePageDocument() throws {
    let data = try PrepSheetRenderer.render(makeContent(), format: .pdf)

    #expect(data.count > 1_000)
    let header = String(decoding: data.prefix(5), as: UTF8.self)
    #expect(header == "%PDF-")

    let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    #expect(document.numberOfPages == 1)

    let page = try #require(document.page(at: 1))
    let box = page.getBoxRect(.mediaBox)
    #expect(box.width == 612)
    #expect(box.height == 792)
}

@MainActor
@Test
func pdfRenderUsesA4MediaBoxWhenRequested() throws {
    let data = try PrepSheetRenderer.render(makeContent(), format: .pdf, pageSize: .a4)

    let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    let page = try #require(document.page(at: 1))
    let box = page.getBoxRect(.mediaBox)
    #expect(box.width == 595)
    #expect(box.height == 842)
}

// MARK: - PNG rendering

@MainActor
@Test
func pngRenderProducesPrintResolutionBitmap() throws {
    let data = try PrepSheetRenderer.render(makeContent(), format: .png)

    let image = try #require(UIImage(data: data))
    let cgImage = try #require(image.cgImage)

    // US Letter at 300 dpi: 8.5in × 11in → 2550 × 3300 px (±2 for rounding).
    #expect(abs(cgImage.width - 2550) <= 2)
    #expect(abs(cgImage.height - 3300) <= 2)
}

@MainActor
@Test
func renderSucceedsWithoutPigmentRecipes() throws {
    let content = makeContent(usesPigments: false, paletteCount: 12)
    let pdf = try PrepSheetRenderer.render(content, format: .pdf)
    let png = try PrepSheetRenderer.render(content, format: .png)

    #expect(pdf.count > 1_000)
    #expect(png.count > 1_000)
}

@MainActor
@Test
func renderSucceedsWithManyRecipes() throws {
    // More recipes than the layout displays — must cap, not overflow.
    let content = makeContent(recipeCount: 24, paletteCount: 24)
    let data = try PrepSheetRenderer.render(content, format: .pdf)
    #expect(data.count > 1_000)
}

// MARK: - AppState export contract

@MainActor
@Test
func exportPrepSheetProcessesValueAndColorAndComposes() async throws {
    let requestedModes = SendableBox<[RefPlaneMode]>([])

    let state = AppState(processOperation: { image, mode, _, _, onProgress in
        requestedModes.update { $0.append(mode) }
        onProgress(1.0)
        return ProcessingResult(
            image: image,
            palette: [Color.gray],
            paletteBands: [0],
            pixelBands: [],
            pigmentRecipes: nil,
            selectedTubes: [],
            clippedRecipeIndices: []
        )
    })
    state.sourceImage = TestImageFactory.makeSolid(width: 64, height: 48, color: .purple)

    let payload = try await state.exportPrepSheet(format: .pdf)

    #expect(requestedModes.value.sorted(by: { $0.rawValue < $1.rawValue }) == [.color, .value])
    #expect(payload.contentType == .pdf)
    #expect(payload.filename.hasPrefix("underpaint-kit-"))
    #expect(payload.filename.hasSuffix(".pdf"))
    let header = String(decoding: payload.data.prefix(5), as: UTF8.self)
    #expect(header == "%PDF-")

    // The progress indicator must be released after composing.
    #expect(state.pipeline.isProcessing == false)
}

@MainActor
@Test
func exportPrepSheetWithoutImageThrows() async {
    let state = AppState(processOperation: { image, _, _, _, _ in
        ProcessingResult(
            image: image,
            palette: [],
            paletteBands: [],
            pixelBands: [],
            pigmentRecipes: nil,
            selectedTubes: [],
            clippedRecipeIndices: []
        )
    })

    await #expect(throws: PrepSheetError.self) {
        _ = try await state.exportPrepSheet(format: .png)
    }
}

@MainActor
@Test
func prepSheetDateStampIsCompactAndStable() {
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 10
    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(from: components)!

    #expect(AppState.prepSheetDateStamp(for: date) == "20260610")
}

// MARK: - Helpers

/// Minimal lock-protected box so the @Sendable process operation can record calls.
private final class SendableBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func update(_ mutate: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutate(&storedValue)
    }
}
