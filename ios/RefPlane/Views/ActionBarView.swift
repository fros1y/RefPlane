import SwiftUI

struct ActionBarView: View {
    @EnvironmentObject private var state: AppState
    @State private var showShareSheet = false
    @State private var exportImage: UIImage?

    var body: some View {
        HStack(spacing: 4) {
            ActionButton(icon: "rectangle.split.2x1", label: "Compare") {
                state.showCompare = true
            }
            .disabled(state.processedImage == nil)

            ActionButton(icon: "square.and.arrow.up", label: "Export") {
                exportImage = state.exportCurrentImage()
                if exportImage != nil { showShareSheet = true }
            }
            .disabled(state.currentDisplayImage == nil)
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = exportImage {
                ShareSheet(items: [img])
            }
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
