import Foundation

/// Tracks the user's morning and afternoon "commute" stops. The stop IDs are
/// stored in the shared App Group so the complication extension can read them
/// without a network call.
@MainActor
class CommuteSlotsManager: ObservableObject {
    static let appGroupSuiteName = "group.org.larner.SFTransitWatch"

    enum Slot: String, CaseIterable {
        case morning
        case afternoon

        var storageKey: String {
            switch self {
            case .morning:   return "commute_morning_stop_id"
            case .afternoon: return "commute_afternoon_stop_id"
            }
        }

        var displayName: String {
            switch self {
            case .morning:   return "Morning"
            case .afternoon: return "Afternoon"
            }
        }

        /// Which slot is active at a given hour. Morning < 12:00, afternoon >= 12:00.
        static func active(at date: Date, calendar: Calendar = .current) -> Slot {
            let hour = calendar.component(.hour, from: date)
            return hour < 12 ? .morning : .afternoon
        }
    }

    @Published var morningStopId: String?
    @Published var afternoonStopId: String?

    private let userDefaults: UserDefaults

    init(userDefaultsSuiteName: String? = CommuteSlotsManager.appGroupSuiteName) {
        self.userDefaults = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        load()
    }

    func stopId(for slot: Slot) -> String? {
        switch slot {
        case .morning:   return morningStopId
        case .afternoon: return afternoonStopId
        }
    }

    func setStopId(_ stopId: String?, for slot: Slot) {
        switch slot {
        case .morning:   morningStopId = stopId
        case .afternoon: afternoonStopId = stopId
        }
        save(slot: slot)
    }

    /// Which slot — if any — the given stop is assigned to.
    func slot(for stopId: String) -> Slot? {
        if morningStopId == stopId { return .morning }
        if afternoonStopId == stopId { return .afternoon }
        return nil
    }

    /// Active slot falling back to whichever is configured when the active
    /// one is empty. Returns nil if neither slot is set.
    func activeSlotWithFallback(at date: Date = .now) -> Slot? {
        let preferred = Slot.active(at: date)
        if stopId(for: preferred) != nil { return preferred }
        let other: Slot = preferred == .morning ? .afternoon : .morning
        return stopId(for: other) != nil ? other : nil
    }

    private func load() {
        morningStopId   = userDefaults.string(forKey: Slot.morning.storageKey)
        afternoonStopId = userDefaults.string(forKey: Slot.afternoon.storageKey)
    }

    private func save(slot: Slot) {
        let value = stopId(for: slot)
        if let value, !value.isEmpty {
            userDefaults.set(value, forKey: slot.storageKey)
        } else {
            userDefaults.removeObject(forKey: slot.storageKey)
        }
    }
}
