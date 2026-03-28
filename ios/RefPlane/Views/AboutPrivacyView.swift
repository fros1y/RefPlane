import SwiftUI

struct AboutPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
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
                    }
                    .padding(.vertical, 4)
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
}
