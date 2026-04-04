import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(UnlockManager.self) private var unlockManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 28) {
                    heroSection
                    featureList
                    purchaseSection
                    footerLinks
                }
                .padding(.horizontal, 24)
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Unlock Underpaint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("paywall.close")
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Process your own photos")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("One purchase, yours forever.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow(icon: "photo.on.rectangle", text: "Load any photo from your library")
            featureRow(icon: "person.2", text: "Supports Family Sharing")
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if unlockManager.purchaseState == .purchasing {
                ProgressView()
                    .padding()
            } else {
                Button(action: { Task { await unlockManager.purchase() } }) {
                    Group {
                        if let product = unlockManager.product {
                            Text("Unlock — \(product.displayPrice)")
                        } else {
                            Text("Unlock Underpaint")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(unlockManager.product == nil)
                .accessibilityIdentifier("paywall.purchase")
            }

            if unlockManager.purchaseState == .pending {
                Label("Purchase pending approval", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = unlockManager.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 10) {
            Button("Restore Purchases") {
                Task { await unlockManager.restorePurchases() }
            }
            .font(.subheadline)
            .accessibilityIdentifier("paywall.restore")

            Button("Redeem Code") {
                redeemCode()
            }
            .font(.subheadline)
            .accessibilityIdentifier("paywall.redeem")
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Redeem

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

#Preview("Paywall") {
    PaywallView()
        .environment(UnlockManager())
}
