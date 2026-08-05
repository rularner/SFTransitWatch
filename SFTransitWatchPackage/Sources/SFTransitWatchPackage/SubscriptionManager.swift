import Foundation
import StoreKit

public enum SubscriptionManagerError: Error, Equatable {
    case productNotFound
    case purchaseCancelled
    case purchaseFailed
    case verificationFailed
    case noActiveSubscription
}

public final class SubscriptionManager {
    /// The monthly product ID. Kept as a named constant for existing callers/tests.
    public static let workerProxyProductID = "org.larner.SFTransitWatch.proxy.monthly"

    /// All product IDs in the Worker Proxy subscription group, shortest period first.
    /// Add the yearly product ID here once it exists in App Store Connect.
    public static let workerProxyProductIDs: [String] = [
        "org.larner.SFTransitWatch.proxy.monthly"
    ]

    public init() {}

    /// Returns the entitlement JWS (`VerificationResult.jwsRepresentation`) of an active, non-revoked worker-proxy
    /// subscription (any tier in the group), or `nil` if there isn't one.
    public func activeEntitlementJWS() async -> String? {
        let ids = Set(Self.workerProxyProductIDs)
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ids.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  let expirationDate = transaction.expirationDate,
                  expirationDate > Date()
            else { continue }
            return result.jwsRepresentation
        }
        return nil
    }

    /// Loads every product in the subscription group and maps each to a display model,
    /// including its eligible introductory offer. Sorted shortest billing period first.
    /// Returns an empty array on any failure (offline, productNotFound).
    public func loadDisplayInfo() async -> [SubscriptionDisplayInfo] {
        guard let products = try? await Product.products(for: Self.workerProxyProductIDs) else {
            return []
        }
        var infos: [SubscriptionDisplayInfo] = []
        for product in products {
            guard let subscription = product.subscription else { continue }
            var intro: IntroOfferInfo?
            if let offer = subscription.introductoryOffer,
               await subscription.isEligibleForIntroOffer {
                intro = Self.introOfferInfo(from: offer)
            }
            infos.append(SubscriptionDisplayInfo(
                productID: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                periodLabel: Self.periodLabel(for: subscription.subscriptionPeriod),
                introOffer: intro
            ))
        }
        return infos.sorted { Self.periodDays($0.periodLabel) < Self.periodDays($1.periodLabel) }
    }

    /// Presents the StoreKit purchase flow for the given product. Returns the
    /// `jwsRepresentation` on success.
    public func purchase(productID: String) async throws -> String {
        let products = try await Product.products(for: [productID])
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
            return verification.jwsRepresentation
        case .userCancelled:
            throw SubscriptionManagerError.purchaseCancelled
        case .pending:
            throw SubscriptionManagerError.purchaseFailed
        @unknown default:
            throw SubscriptionManagerError.purchaseFailed
        }
    }

    /// Force-refreshes entitlements from Apple's servers (may prompt for Apple ID
    /// sign-in), then returns the active worker-proxy subscription's
    /// `jwsRepresentation`. Throws `.noActiveSubscription` if none is found.
    public func restore() async throws -> String {
        try await AppStore.sync()
        guard let jws = await activeEntitlementJWS() else {
            throw SubscriptionManagerError.noActiveSubscription
        }
        return jws
    }

    // MARK: - StoreKit → value-type mapping

    private static func introOfferInfo(from offer: Product.SubscriptionOffer) -> IntroOfferInfo {
        let mode: PaymentMode
        switch offer.paymentMode {
        case .freeTrial: mode = .freeTrial
        case .payAsYouGo: mode = .payAsYouGo
        case .payUpFront: mode = .payUpFront
        default: mode = .payAsYouGo
        }
        let price = offer.paymentMode == .freeTrial ? "Free" : offer.displayPrice
        return IntroOfferInfo(
            displayPrice: price,
            periodLabel: unitLabel(for: offer.period.unit),
            periodCount: offer.periodCount,
            paymentMode: mode
        )
    }

    private static func periodLabel(for period: Product.SubscriptionPeriod) -> String {
        let unit = unitLabel(for: period.unit)
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    private static func unitLabel(for unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }

    /// Approximate day count for sorting tiers by billing period length.
    private static func periodDays(_ label: String) -> Int {
        if label.contains("year") { return 365 }
        if label.contains("month") { return 30 }
        if label.contains("week") { return 7 }
        return 1
    }
}
