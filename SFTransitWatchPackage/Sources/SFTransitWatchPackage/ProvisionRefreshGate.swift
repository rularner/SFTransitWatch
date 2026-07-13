import Foundation

/// Decides whether the passive, foreground-triggered subscription refresh
/// should call `/self-provision` again.
///
/// The worker rate-limits `/self-provision` to a handful of requests per IP
/// per 10 minutes — a budget sized for occasional, manual provisioning. Prior
/// to this gate, `refreshSubscriptionIfNeeded()` called the endpoint on every
/// single foreground event (app switch, Face ID prompt, returning from the
/// StoreKit sheet, etc.), which could exhaust that budget before a real
/// Subscribe tap got through. Subscription status changes rarely, so an
/// hourly cap is enough to catch cancellations promptly while leaving the
/// budget free for actual purchase attempts.
public enum ProvisionRefreshGate {
    public static let minimumInterval: TimeInterval = 60 * 60

    public static func shouldRefresh(lastRefreshAt: Date?, now: Date) -> Bool {
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= minimumInterval
    }
}
