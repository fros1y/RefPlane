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
