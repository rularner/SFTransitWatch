import Foundation

@MainActor
public class AlertSettingsManager: ObservableObject {
    public static let appGroupSuiteName = CommuteSlotsManager.appGroupSuiteName

    // Public so views can use @AppStorage(AlertSettingsManager.alertEnabledKey, store: ...)
    public static let alertEnabledKey = "alert_enabled"

    // Fixed lead window: fire notification up to this many minutes before departure deadline.
    public static let alertLeadMinutes = 5

    // Radius used by BackgroundRefreshController for at-stop detection.
    public static let atStopRadiusMeters: Double = 100

    private static func travelKey(_ slot: CommuteSlotsManager.Slot) -> String {
        "alert_travel_\(slot.rawValue)"
    }
    private static func windowStartKey(_ slot: CommuteSlotsManager.Slot) -> String {
        "alert_window_start_\(slot.rawValue)"
    }
    private static func windowEndKey(_ slot: CommuteSlotsManager.Slot) -> String {
        "alert_window_end_\(slot.rawValue)"
    }
    private static func suppressedKey(_ slot: CommuteSlotsManager.Slot) -> String {
        "alert_at_stop_suppressed_\(slot.rawValue)"
    }

    private let defaults: UserDefaults

    // Read from UserDefaults each time so all instances stay in sync without observation.
    // Views bind to this key via @AppStorage; BackgroundRefreshController reads it here.
    public var alertsEnabled: Bool {
        get { defaults.object(forKey: Self.alertEnabledKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.alertEnabledKey)
        }
    }

    public init(userDefaultsSuiteName: String? = AlertSettingsManager.appGroupSuiteName) {
        self.defaults = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    // MARK: - Travel time

    public func travelMinutes(for slot: CommuteSlotsManager.Slot) -> Int {
        defaults.integer(forKey: Self.travelKey(slot))
    }

    public func setTravelMinutes(_ minutes: Int, for slot: CommuteSlotsManager.Slot) {
        objectWillChange.send()
        defaults.set(max(0, minutes), forKey: Self.travelKey(slot))
    }

    // MARK: - Alert windows

    public func windowStart(for slot: CommuteSlotsManager.Slot) -> DateComponents {
        parseHHMM(defaults.string(forKey: Self.windowStartKey(slot)) ?? "00:00")
    }

    public func windowEnd(for slot: CommuteSlotsManager.Slot) -> DateComponents {
        parseHHMM(defaults.string(forKey: Self.windowEndKey(slot)) ?? "23:59")
    }

    public func setWindowStart(_ dc: DateComponents, for slot: CommuteSlotsManager.Slot) {
        objectWillChange.send()
        defaults.set(formatHHMM(dc), forKey: Self.windowStartKey(slot))
        // Clamp end so that end >= start.
        if minuteOfDay(windowEnd(for: slot)) < minuteOfDay(dc) {
            defaults.set(formatHHMM(dc), forKey: Self.windowEndKey(slot))
        }
    }

    public func setWindowEnd(_ dc: DateComponents, for slot: CommuteSlotsManager.Slot) {
        objectWillChange.send()
        let clamped = minuteOfDay(dc) < minuteOfDay(windowStart(for: slot))
            ? windowStart(for: slot)
            : dc
        defaults.set(formatHHMM(clamped), forKey: Self.windowEndKey(slot))
    }

    public func isWithinWindow(
        for slot: CommuteSlotsManager.Slot,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let nowMins = minuteOfDay(
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date)
        )
        let startMins = minuteOfDay(windowStart(for: slot))
        let endMins   = minuteOfDay(windowEnd(for: slot))
        return nowMins >= startMins && nowMins <= endMins
    }

    // MARK: - At-stop suppression

    public func isAtStopSuppressed(
        for slot: CommuteSlotsManager.Slot,
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let stored = defaults.object(forKey: Self.suppressedKey(slot)) as? Date else {
            return false
        }
        return calendar.isDate(stored, inSameDayAs: date)
    }

    public func suppressAtStop(for slot: CommuteSlotsManager.Slot) {
        objectWillChange.send()
        defaults.set(Date.now, forKey: Self.suppressedKey(slot))
    }

    public func clearAtStopSuppression(for slot: CommuteSlotsManager.Slot) {
        objectWillChange.send()
        defaults.removeObject(forKey: Self.suppressedKey(slot))
    }

    // MARK: - Alert gate

    /// Returns the first arrival the user can reach that falls within the imminent
    /// lead window, or nil if no notification should fire right now.
    public func qualifyingArrival(
        from arrivals: [BusArrival],
        for slot: CommuteSlotsManager.Slot,
        at date: Date = .now
    ) -> BusArrival? {
        guard alertsEnabled else { return nil }
        guard isWithinWindow(for: slot, at: date) else { return nil }
        guard !isAtStopSuppressed(for: slot, at: date) else { return nil }
        let travel = travelMinutes(for: slot)
        guard let candidate = arrivals.first(where: { $0.minutesAway >= travel }) else { return nil }
        guard candidate.minutesAway <= travel + Self.alertLeadMinutes else { return nil }
        return candidate
    }

    // MARK: - Private helpers

    private func parseHHMM(_ string: String) -> DateComponents {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        var dc = DateComponents()
        dc.hour   = parts.count > 0 ? parts[0] : 0
        dc.minute = parts.count > 1 ? parts[1] : 0
        return dc
    }

    private func formatHHMM(_ dc: DateComponents) -> String {
        String(format: "%02d:%02d", dc.hour ?? 0, dc.minute ?? 0)
    }

    private func minuteOfDay(_ dc: DateComponents) -> Int {
        minuteOfDay(hour: dc.hour ?? 0, minute: dc.minute ?? 0)
    }

    private func minuteOfDay(hour: Int, minute: Int) -> Int {
        hour * 60 + minute
    }
}
