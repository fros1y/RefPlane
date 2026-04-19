import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(UnlockManager.self) private var unlockManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    heroSection
                    storySection
                    privacySection
                    purchaseSection
                    footerLinks
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
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

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Turn your photos into painting prep.")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("One purchase. Your references stay private and on-device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var storySection: some View {
        VStack(spacing: 14) {
            PaywallStoryRow(
                title: "See the values before you paint",
                caption: "Block in the big planes fast with tonal and value studies.",
                preview: AnyView(ValueStoryPreview())
            )

            PaywallStoryRow(
                title: "Mix real paints, predicted physically",
                caption: "Turn simplified color areas into tube recipes you can actually mix.",
                preview: AnyView(RecipeStoryPreview())
            )

            PaywallStoryRow(
                title: "Isolate your subject with Spatial depth",
                caption: "Knock back cluttered backgrounds so the painting problem gets simpler.",
                preview: AnyView(DepthStoryPreview())
            )
        }
    }

    private var privacySection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)

            Text("Every photo stays on your device. No accounts, no analytics, no tracking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if unlockManager.purchaseState == .purchasing {
                ProgressView()
                    .padding()
            } else {
                Button(action: { Task { await unlockManager.purchase() } }) {
                    Group {
                        if let product = unlockManager.product {
                            Text("Unlock Underpaint — \(product.displayPrice)")
                        } else {
                            Text("Unlock Underpaint")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
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

private struct PaywallStoryRow: View {
    let title: String
    let caption: String
    let preview: AnyView

    var body: some View {
        HStack(spacing: 14) {
            preview
                .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ValueStoryPreview: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("sample-statue")
                .resizable()
                .scaledToFill()
                .grayscale(1)
                .contrast(1.1)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(white: Double(index) / 4))
                        .frame(width: 42, height: 10)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(10)
        }
    }
}

private struct RecipeStoryPreview: View {
    private let rows = [
        ("Cad Red Med", "3"),
        ("Yellow Ochre", "1"),
        ("Titanium White", "4"),
    ]

    var body: some View {
        ZStack {
            Image("sample-still-life")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: row.0))
                            .frame(width: 10, height: 10)
                        Text(row.0)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(row.1) parts")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(10)
        }
    }

    private func color(for pigment: String) -> Color {
        switch pigment {
        case "Cad Red Med":
            return Color(red: 0.74, green: 0.22, blue: 0.18)
        case "Yellow Ochre":
            return Color(red: 0.8, green: 0.66, blue: 0.35)
        default:
            return Color(red: 0.94, green: 0.93, blue: 0.9)
        }
    }
}

private struct DepthStoryPreview: View {
    private var previewImage: Image {
        if let url = Bundle.main.url(forResource: "chair-spatial", withExtension: "heic"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return Image(uiImage: image)
        }

        return Image("sample-statue")
    }

    var body: some View {
        ZStack {
            previewImage
                .resizable()
                .scaledToFill()
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.4),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Foreground")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9), in: Capsule())

                Spacer()

                Text("Compressed background")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(10)
        }
    }
}

#Preview("Paywall") {
    PaywallView()
        .environment(UnlockManager())
}
