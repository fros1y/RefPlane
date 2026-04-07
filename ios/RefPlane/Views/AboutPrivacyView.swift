import StoreKit
import SwiftUI
import TipKit
import UIKit

struct AboutPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Environment(UnlockManager.self) private var unlockManager
    @State private var didCopySettings = false
    @State private var showPaywall = false

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
        @Bindable var unlockManager = unlockManager
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

                Section("Purchase") {
                    HStack {
                        if unlockManager.isUnlocked {
                            Label("Unlocked", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Free — Samples Only", systemImage: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.body)

                    if !unlockManager.isUnlocked {
                        Button(action: { showPaywall = true }) {
                            Label("Unlock Full App", systemImage: "paintpalette")
                        }
                        .accessibilityIdentifier("about.unlock")
                    }

                    Button(action: { Task { await unlockManager.restorePurchases() } }) {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("about.restore")

                    if !unlockManager.isUnlocked {
                        Button(action: redeemCode) {
                            Label("Redeem Code", systemImage: "giftcard")
                        }
                        .accessibilityIdentifier("about.redeem")
                    }

#if DEBUG
                    Toggle(isOn: $unlockManager.debugUnlockOverride) {
                        Label("Force Paid Mode (Debug)", systemImage: "ladybug.fill")
                    }
                    .onChange(of: unlockManager.debugUnlockOverride) { _, _ in
                        Task { await unlockManager.refreshPurchaseStatus() }
                    }
#endif
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

#if DEBUG
                Section("Tips") {
                    Button("Reset Tip Datastore") {
                        AppTips.resetForTesting()
                    }
                    .accessibilityIdentifier("about.debug.reset-tips")

                    Button("Show All Tips") {
                        AppTips.showAllForTesting()
                    }
                    .accessibilityIdentifier("about.debug.show-all-tips")
                }
#endif
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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

    private func redeemCode() {
        #if !targetEnvironment(simulator)
        Task {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }
            do {
                try await AppStore.presentOfferCodeRedeemSheet(in: windowScene)
            } catch {
                unlockManager.errorMessage = error.localizedDescription
            }
        }
        #endif
    }
}
