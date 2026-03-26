import SwiftUI

struct ActionBarView: View {
    @EnvironmentObject private var state: AppState

    var showsDismissButton: Bool = false
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Adjustments")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(state.activeMode.label) Study")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if showsDismissButton, let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "sidebar.trailing")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Hide adjustments")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
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
