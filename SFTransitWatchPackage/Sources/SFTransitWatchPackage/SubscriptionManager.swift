import Foundation
import StoreKit

public enum SubscriptionManagerError: Error, Equatable {
    case productNotFound
    case purchaseCancelled
    case purchaseFailed
    case verificationFailed
}

public final class SubscriptionManager {
    public static let workerProxyProductID = "org.larner.SFTransitWatch.workerproxy.monthly"

    public init() {}

    /// Returns the `originalTransactionId` of an active, non-revoked worker-proxy
    /// subscription entitlement, or `nil` if there isn't one.
    public func activeOriginalTransactionId() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.workerProxyProductID,
                  transaction.revocationDate == nil,
                  let expirationDate = transaction.expirationDate,
                  expirationDate > Date()
            else { continue }
            return String(transaction.originalID)
        }
        return nil
    }

    /// Presents the StoreKit purchase flow for the worker-proxy subscription.
    /// Returns the `originalTransactionId` on success.
    public func purchase() async throws -> String {
        let products = try await Product.products(for: [Self.workerProxyProductID])
        guard let product = products.first else {
            throw SubscriptionManagerError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw SubscriptionManagerError.verificationFailed
            }
            await transaction.finish()
            return String(transaction.originalID)
        case .userCancelled:
            throw SubscriptionManagerError.purchaseCancelled
        case .pending:
            throw SubscriptionManagerError.purchaseFailed
        @unknown default:
            throw SubscriptionManagerError.purchaseFailed
        }
    }
}
