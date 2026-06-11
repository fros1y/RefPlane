import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(UnlockManager.self) private var unlockManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    featureList
                    privacyLine
                    purchaseSection
                    footerLinks
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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

            Text("Turn your photos into painting prep")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("One purchase, yours forever. Family Sharing included.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 20) {
            featureRow(
                icon: "square.stack.3d.up",
                title: "See the values before you paint",
                detail: "Break any photo into the value planes that matter, with thresholds you control."
            )
            featureRow(
                icon: "eyedropper.halffull",
                title: "Mix real paints, predicted physically",
                detail: "Pigment recipes computed with Kubelka–Munk mixing — parts of real tubes, not screen colors."
            )
            featureRow(
                icon: "person.and.background.dotted",
                title: "Isolate your subject with depth",
                detail: "Blur, compress, or remove the background using on-device depth estimation."
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyLine: some View {
        Label(
            "Every photo stays on your device. No accounts, no tracking.",
            systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
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
