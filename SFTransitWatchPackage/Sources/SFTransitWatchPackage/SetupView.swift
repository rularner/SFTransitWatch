import SwiftUI

public struct SetupView: View {
    let canSubscribe: Bool
    let tiers: [SubscriptionDisplayInfo]
    let isPurchasing: Bool
    let onSubscribe: (String) -> Void
    let onUseKey: () -> Void

    public init(canSubscribe: Bool, tiers: [SubscriptionDisplayInfo], isPurchasing: Bool, onSubscribe: @escaping (String) -> Void, onUseKey: @escaping () -> Void) {
        self.canSubscribe = canSubscribe
        self.tiers = tiers
        self.isPurchasing = isPurchasing
        self.onSubscribe = onSubscribe
        self.onUseKey = onUseKey
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "bus.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)

                    VStack(spacing: 6) {
                        Text("SF Transit Watch")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Set up data access to see nearby stops.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("SF Transit Watch. Set up data access to see nearby stops.")

                VStack(spacing: 12) {
                    if canSubscribe {
                        PaywallView(tiers: tiers, isPurchasing: isPurchasing, onSubscribe: onSubscribe)
                    }

                    VStack(spacing: 4) {
                        Button("Use 511.org API Key", action: onUseKey)
                            .buttonStyle(.bordered)
                        Text("Free key from 511.org — set it up yourself")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .interactiveDismissDisabled(true)
    }
}

#if DEBUG
#Preview("Can subscribe") {
    SetupView(
        canSubscribe: true,
        tiers: [SubscriptionDisplayInfo(productID: "monthly", displayName: "Monthly", displayPrice: "$1.99", periodLabel: "month", introOffer: nil)],
        isPurchasing: false,
        onSubscribe: { _ in },
        onUseKey: {}
    )
}

#Preview("No subscription") {
    SetupView(canSubscribe: false, tiers: [], isPurchasing: false, onSubscribe: { _ in }, onUseKey: {})
}
#endif
