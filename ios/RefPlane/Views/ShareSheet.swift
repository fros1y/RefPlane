import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                onCompletion?()
            }
        }

        // iPad requires a source anchor for UIActivityViewController's popover presentation.
        if let popover = vc.popoverPresentationController,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ExportShareActivityRouter {
    // UIKit exposes Save to Files via a raw identifier rather than a public static constant.
    static let saveToFilesActivityType = UIActivity.ActivityType(
        rawValue: "com.apple.DocumentManagerUICore.SaveToFiles"
    )

    static func usesFileURL(_ activityType: UIActivity.ActivityType?) -> Bool {
        guard let activityType else { return false }
        return activityType == .airDrop || activityType == saveToFilesActivityType
    }
}

final class ExportImageActivityItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let subject: String

    init(image: UIImage, subject: String) {
        self.image = image
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        guard !ExportShareActivityRouter.usesFileURL(activityType) else { return nil }
        return image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}

final class ExportFileActivityItemSource: NSObject, UIActivityItemSource {
    private let fileURL: URL
    private let subject: String

    init(fileURL: URL, subject: String) {
        self.fileURL = fileURL
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        guard ExportShareActivityRouter.usesFileURL(activityType) else { return nil }
        return fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}
