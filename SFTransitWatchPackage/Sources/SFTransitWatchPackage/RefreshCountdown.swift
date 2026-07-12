import Foundation

/// Drives the single foreground auto-refresh cadence for the arrivals views.
///
/// Previously each `BusArrivalView` ran two independent `Timer.publish` sources
/// — a 1s countdown that fired at zero *and* a separate interval timer — which
/// double-fired `loadArrivals()` every cycle. This collapses that into one
/// source: tick once per second, refresh exactly when the countdown wraps.
@MainActor
public final class RefreshCountdown: ObservableObject {
    /// Seconds shown in the "↻ Ns" label; also the time until the next refresh.
    @Published public private(set) var secondsRemaining: Int

    public private(set) var interval: Int

    public init(interval: Int) {
        self.interval = interval
        self.secondsRemaining = interval
    }

    /// Change the refresh cadence (e.g. when the client's poll interval backs
    /// off). Clamps the remaining time down so we never wait longer than the
    /// new, shorter interval; a longer interval leaves the current cycle intact.
    public func setInterval(_ newInterval: Int) {
        interval = newInterval
        if secondsRemaining > newInterval {
            secondsRemaining = newInterval
        }
    }

    /// Advance the countdown by one second.
    /// - Returns: `true` when the countdown has wrapped and a refresh should fire.
    @discardableResult
    public func tick() -> Bool {
        if secondsRemaining <= 1 {
            secondsRemaining = interval
            return true
        }
        secondsRemaining -= 1
        return false
    }

    /// Restart the countdown from `interval` (e.g. after a manual/refreshable load).
    public func reset() {
        secondsRemaining = interval
    }
}
