import SwiftUI

/// Renders the subscription purchase block: selectable tiers, the price/period,
/// any eligible introductory offer, the auto-renewal disclosure, and the required
/// Terms of Use + Privacy Policy links. Embedded by both the onboarding `SetupView`
/// and the phone `SettingsView`.
///
/// `tiers` is injected (loaded by the host from `SubscriptionManager.loadDisplayInfo()`),
/// so this view compiles and renders in previews/snapshots without StoreKit.
public struct PaywallView: View {
    private let tiers: [SubscriptionDisplayInfo]
    private let isPurchasing: Bool
    private let onSubscribe: (String) -> Void
    private let isRestoring: Bool
    private let onRestore: () -> Void

    @State private var selectedProductID: String?

    public init(
        tiers: [SubscriptionDisplayInfo],
        isPurchasing: Bool,
        onSubscribe: @escaping (String) -> Void,
        isRestoring: Bool,
        onRestore: @escaping () -> Void
    ) {
        self.tiers = tiers
        self.isPurchasing = isPurchasing
        self.onSubscribe = onSubscribe
        self.isRestoring = isRestoring
        self.onRestore = onRestore
    }

    private var selectedTier: SubscriptionDisplayInfo? {
        tiers.first { $0.productID == selectedProductID } ?? tiers.first
    }

    public var body: some View {
        VStack(spacing: 12) {
            if tiers.isEmpty {
                ProgressView()
                Text("Loading subscription options…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if tiers.count > 1 {
                    ForEach(tiers) { tier in
                        tierRow(tier)
                    }
                } else if let tier = tiers.first {
                    singleTierSummary(tier)
                }

                Button(isPurchasing ? "Subscribing…" : "Subscribe") {
                    if let id = selectedTier?.productID { onSubscribe(id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing || selectedTier == nil)

                if let tier = selectedTier {
                    Text(tier.autoRenewalDisclosure)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(isRestoring ? "Restoring…" : "Restore Purchases") {
                    onRestore()
                }
                .buttonStyle(.bordered)
                .disabled(isPurchasing || isRestoring)

                legalLinks
            }
        }
        .onAppear {
            if selectedProductID == nil { selectedProductID = tiers.first?.productID }
        }
    }

    @ViewBuilder
    private func tierRow(_ tier: SubscriptionDisplayInfo) -> some View {
        Button {
            selectedProductID = tier.productID
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.headline)
                    Text(tier.pricePerPeriod)
                        .font(.subheadline)
                    if let intro = tier.introOffer {
                        Text(intro.summary)
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                Spacer()
                Image(systemName: tier.productID == selectedTier?.productID ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func singleTierSummary(_ tier: SubscriptionDisplayInfo) -> some View {
        VStack(spacing: 2) {
            Text(tier.pricePerPeriod)
                .font(.headline)
            if let intro = tier.introOffer {
                Text(intro.summary)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        HStack(spacing: 12) {
            Link("Terms of Use", destination: SubscriptionLegal.termsOfUseURL)
            Text("·").foregroundStyle(.secondary)
            Link("Privacy Policy", destination: SubscriptionLegal.privacyPolicyURL)
        }
        .font(.caption2)

        #if os(watchOS)
        // watchOS `Link` only offers iPhone handoff and can't open a browser,
        // so the terms wouldn't actually be readable on-watch without this.
        VStack(spacing: 2) {
            Text(SubscriptionLegal.termsOfUseURL.absoluteString)
            Text(SubscriptionLegal.privacyPolicyURL.absoluteString)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        #endif
    }
}

#if DEBUG
#Preview("Single tier") {
    PaywallView(
        tiers: [SubscriptionDisplayInfo(productID: "monthly", displayName: "Monthly", displayPrice: "$1.99", periodLabel: "month", introOffer: nil)],
        isPurchasing: false,
        onSubscribe: { _ in },
        isRestoring: false,
        onRestore: {}
    )
    .padding()
}

#Preview("Multi tier with trial") {
    PaywallView(
        tiers: [
            SubscriptionDisplayInfo(productID: "monthly", displayName: "Monthly", displayPrice: "$1.99", periodLabel: "month",
                                    introOffer: IntroOfferInfo(displayPrice: "Free", periodLabel: "week", periodCount: 1, paymentMode: .freeTrial)),
            SubscriptionDisplayInfo(productID: "yearly", displayName: "Yearly", displayPrice: "$19.99", periodLabel: "year", introOffer: nil),
        ],
        isPurchasing: false,
        onSubscribe: { _ in },
        isRestoring: false,
        onRestore: {}
    )
    .padding()
}

#Preview("Loading") {
    PaywallView(tiers: [], isPurchasing: false, onSubscribe: { _ in }, isRestoring: false, onRestore: {})
        .padding()
}
#endif
