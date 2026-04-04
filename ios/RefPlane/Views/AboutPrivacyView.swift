import SwiftUI
import UIKit

struct AboutPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var didCopySettings = false

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private var gitRevisionString: String {
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

    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Underpaint")
                                .font(.headline)
                            Spacer()
                            Text(appVersionString)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }

                        Text("Reference preparation for painting and drawing on iPhone and iPad.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Created by Martin Galese.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Build \(gitRevisionString)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)

                    Button(action: copyCurrentSettings) {
                        Label(
                            didCopySettings ? "Copied Settings" : "Copy Settings",
                            systemImage: didCopySettings ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }
                    .accessibilityIdentifier("about.copy-settings")
                }

                Section("Privacy") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Underpaint collects no personal data.")
                        Text("The app uses no analytics, no tracking, and no accounts.")
                        Text("Images you choose are processed on-device.")
                    }
                    .font(.body)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func copyCurrentSettings() {
        UIPasteboard.general.string = state.currentSettingsDescription()
        didCopySettings = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            didCopySettings = false
        }
    }
}
