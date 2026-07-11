import Foundation

/// How an introductory offer is billed. Mirrors StoreKit's payment modes but is
/// StoreKit-free so it can be constructed and unit-tested without StoreKitTest.
public enum PaymentMode: Equatable {
    case freeTrial
    case payAsYouGo
    case payUpFront
}

/// The eligible introductory offer for a subscription tier, pre-formatted for display.
public struct IntroOfferInfo: Equatable {
    public let displayPrice: String   // localized, e.g. "Free" or "$0.99"
    public let periodLabel: String    // "day" | "week" | "month" | "year"
    public let periodCount: Int       // number of intro periods, e.g. 7
    public let paymentMode: PaymentMode

    public init(displayPrice: String, periodLabel: String, periodCount: Int, paymentMode: PaymentMode) {
        self.displayPrice = displayPrice
        self.periodLabel = periodLabel
        self.periodCount = periodCount
        self.paymentMode = paymentMode
    }

    private var pluralizedPeriod: String {
        periodCount == 1 ? periodLabel : "\(periodLabel)s"
    }

    /// Human-readable summary of the offer, e.g. "Free for 7 days",
    /// "$0.99/month for the first 3 months", "$4.99 for the first 6 months".
    public var summary: String {
        switch paymentMode {
        case .freeTrial:
            return "Free for \(periodCount) \(pluralizedPeriod)"
        case .payAsYouGo:
            return "\(displayPrice)/\(periodLabel) for the first \(periodCount) \(pluralizedPeriod)"
        case .payUpFront:
            return "\(displayPrice) for the first \(periodCount) \(pluralizedPeriod)"
        }
    }
}

/// One selectable subscription tier, pre-formatted for display. Localized price and
/// period come straight from StoreKit at runtime (see `SubscriptionManager`), so this
/// type never hardcodes currency or duration.
public struct SubscriptionDisplayInfo: Equatable, Identifiable {
    public let productID: String
    public let displayName: String    // e.g. "Monthly", "Yearly"
    public let displayPrice: String   // localized, e.g. "$1.99"
    public let periodLabel: String    // "month" | "year" | "3 months" ...
    public let introOffer: IntroOfferInfo?

    public init(productID: String, displayName: String, displayPrice: String, periodLabel: String, introOffer: IntroOfferInfo?) {
        self.productID = productID
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.periodLabel = periodLabel
        self.introOffer = introOffer
    }

    public var id: String { productID }

    /// e.g. "$1.99/month".
    public var pricePerPeriod: String {
        "\(displayPrice)/\(periodLabel)"
    }

    /// The full auto-renewal disclosure required by App Store Review Guideline 3.1.2,
    /// including introductory-offer terms when an eligible offer is present.
    public var autoRenewalDisclosure: String {
        let renewClause = "This subscription automatically renews for \(pricePerPeriod) unless it is canceled at least 24 hours before the end of the current period. Your Apple Account is charged for renewal within 24 hours before the end of the current period. You can manage or cancel the subscription in your Account Settings after purchase."
        if let intro = introOffer {
            return "\(intro.summary), then \(pricePerPeriod). Payment is charged to your Apple Account at confirmation of purchase. \(renewClause)"
        }
        return "Payment of \(pricePerPeriod) is charged to your Apple Account at confirmation of purchase. \(renewClause)"
    }
}
