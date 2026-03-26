import SwiftUI

struct ActionBarView: View {
    @EnvironmentObject private var state: AppState
    @State private var exportItem: ExportItem?

    var body: some View {
        HStack(spacing: 4) {
            ActionButton(icon: "rectangle.split.2x1", label: "Compare", isActive: state.compareMode) {
                state.compareMode.toggle()
            }
            .disabled(state.displayBaseImage == nil)

            ActionButton(icon: "square.and.arrow.up", label: "Export") {
                if let img = state.exportCurrentImage() {
                    exportItem = ExportItem(image: img)
                }
            }
            .disabled(state.currentDisplayImage == nil)
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.image])
        }
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActionButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(isActive ? .blue : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isActive ? Color.blue.opacity(0.15) : Color.white.opacity(0.07))
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
