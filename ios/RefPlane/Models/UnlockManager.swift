import StoreKit
import Observation

@Observable
@MainActor
class UnlockManager {

    // MARK: - Product Configuration

    static let productID = "com.refplane.app.fullunlock"

    // MARK: - Published State

    private(set) var isUnlocked = false
    private(set) var purchaseState: PurchaseState = .unknown
    private(set) var product: Product?
    var errorMessage: String?

    // MARK: - Private

    @ObservationIgnored
    private var transactionListener: Task<Void, Never>?

    // MARK: - Init

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProduct()
            await refreshPurchaseStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    func purchase() async {
        guard let product else {
            errorMessage = "Product not available. Please try again later."
            return
        }

        purchaseState = .purchasing

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshPurchaseStatus()

            case .userCancelled:
                purchaseState = isUnlocked ? .unlocked : .locked

            case .pending:
                purchaseState = .pending

            @unknown default:
                purchaseState = isUnlocked ? .unlocked : .locked
            }
        } catch {
            errorMessage = error.localizedDescription
            purchaseState = .error
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Product Loading

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            errorMessage = "Could not load product information."
        }
    }

    // MARK: - Entitlement Check

    func refreshPurchaseStatus() async {
        var foundEntitlement = false

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.productID {
                foundEntitlement = true
                break
            }
        }

        isUnlocked = foundEntitlement
        purchaseState = foundEntitlement ? .unlocked : .locked
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await transaction.finish()
                    await self?.refreshPurchaseStatus()
                }
            }
        }
    }

    // MARK: - Verification

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}

// MARK: - Purchase State

enum PurchaseState: Equatable {
    case unknown
    case locked
    case unlocked
    case purchasing
    case pending
    case error
}
