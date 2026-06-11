import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Prep sheet model

enum PrepSheetFormat: String, CaseIterable {
    case pdf
    case png

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .png: return .png
        }
    }

    var fileExtension: String { rawValue }
}

enum PrepSheetPageSize {
    case usLetter
    case a4

    /// Page size in points (1 pt = 1/72 in).
    var pointSize: CGSize {
        switch self {
        case .usLetter: return CGSize(width: 612, height: 792)
        case .a4:       return CGSize(width: 595, height: 842)
        }
    }
}

/// Snapshot of everything the prep sheet needs, captured before rendering
/// so the layout is a pure function of its inputs.
struct PrepSheetContent {
    var referenceImage: UIImage
    var valueImage: UIImage
    var colorImage: UIImage
    var paletteColors: [Color]
    var pigmentRecipes: [PigmentRecipe]?
    var valueLevels: Int
    var valueDistributionName: String
    var colorCount: Int
    var usesPigments: Bool
    var date: Date = Date()
}

enum PrepSheetError: LocalizedError {
    case noImageLoaded
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noImageLoaded:
            return "Load a reference image before exporting a Prep Sheet."
        case .renderFailed:
            return "The Prep Sheet could not be rendered. Please try again."
        }
    }
}

// MARK: - Renderer

@MainActor
enum PrepSheetRenderer {
    /// Print resolution for raster output. PDF text stays vector.
    static let rasterScale: CGFloat = 300.0 / 72.0

    static func render(
        _ content: PrepSheetContent,
        format: PrepSheetFormat,
        pageSize: PrepSheetPageSize = .usLetter
    ) throws -> Data {
        let size = pageSize.pointSize
        let layout = PrepSheetLayoutView(content: content, pageSize: size)

        let renderer = ImageRenderer(content: layout)
        renderer.proposedSize = ProposedViewSize(size)

        switch format {
        case .png:
            renderer.scale = rasterScale
            guard let data = renderer.uiImage?.pngData() else {
                throw PrepSheetError.renderFailed
            }
            return data

        case .pdf:
            let data = NSMutableData()
            var mediaBox = CGRect(origin: .zero, size: size)
            renderer.render { _, renderInContext in
                guard let consumer = CGDataConsumer(data: data),
                      let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
                else {
                    return
                }
                pdfContext.beginPDFPage(nil)
                renderInContext(pdfContext)
                pdfContext.endPDFPage()
                pdfContext.closePDF()
            }
            guard data.length > 0 else {
                throw PrepSheetError.renderFailed
            }
            return data as Data
        }
    }
}
