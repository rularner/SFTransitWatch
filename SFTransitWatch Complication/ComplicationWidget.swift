import SFTransitWatchPackage
import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct NextArrivalEntry: TimelineEntry {
    let date: Date
    let slot: CommuteSlotsManager.Slot?
    let stopName: String
    let route: String
    let arrivalTime: Date?
    let isConfigured: Bool

    static let placeholder = NextArrivalEntry(
        date: .now,
        slot: .morning,
        stopName: "Market & 4th",
        route: "38",
        arrivalTime: Date().addingTimeInterval(4 * 60),
        isConfigured: true
    )

    static let unconfigured = NextArrivalEntry(
        date: .now,
        slot: nil,
        stopName: "",
        route: "",
        arrivalTime: nil,
        isConfigured: false
    )
}

// MARK: - Shared snapshot read

private enum SnapshotStore {
    static let defaults = UserDefaults(suiteName: CommuteSlotsManager.appGroupSuiteName) ?? .standard

    static func snapshot(for slot: CommuteSlotsManager.Slot, at date: Date) -> NextArrivalEntry? {
        let stopName = defaults.string(forKey: ComplicationUpdater.StorageKey.stopName(slot)) ?? ""
        let route = defaults.string(forKey: ComplicationUpdater.StorageKey.route(slot)) ?? ""
        let arrivalTime = defaults.object(forKey: ComplicationUpdater.StorageKey.arrivalTime(slot)) as? Date
        let configuredStopId = defaults.string(forKey: slot.storageKey) ?? ""

        guard !configuredStopId.isEmpty, !stopName.isEmpty else { return nil }

        return NextArrivalEntry(
            date: date,
            slot: slot,
            stopName: stopName,
            route: route,
            arrivalTime: arrivalTime,
            isConfigured: true
        )
    }

    /// Returns the best-effort entry at `date`, falling back to the other slot
    /// when the active slot isn't configured.
    static func entry(at date: Date) -> NextArrivalEntry {
        let preferred = CommuteSlotsManager.Slot.active(at: date)
        if let entry = snapshot(for: preferred, at: date) { return entry }
        let other: CommuteSlotsManager.Slot = preferred == .morning ? .afternoon : .morning
        if let entry = snapshot(for: other, at: date) { return entry }
        return .unconfigured
    }
}

// MARK: - Timeline Provider

struct NextArrivalProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextArrivalEntry {
        NextArrivalEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NextArrivalEntry) -> Void) {
        completion(SnapshotStore.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextArrivalEntry>) -> Void) {
        let now = Date.now
        var entries: [NextArrivalEntry] = [SnapshotStore.entry(at: now)]

        // Emit a second entry at the next slot boundary so the complication
        // swaps automatically at noon (or next-day midnight) even if no
        // intervening reload fires.
        if let boundary = Self.nextSlotBoundary(after: now) {
            entries.append(SnapshotStore.entry(at: boundary))
        }

        // Reload every 5 minutes so the watch app's freshly written arrivalTime
        // is picked up. Text(date, style: .relative) handles the per-second
        // countdown automatically without additional entries.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }

    /// Next time the active slot changes — noon today, or midnight tomorrow,
    /// whichever comes first.
    static func nextSlotBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)
        let midnightTomorrow = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        let candidates = [noon, midnightTomorrow].compactMap { $0 }.filter { $0 > date }
        return candidates.min()
    }
}

// MARK: - Views

extension NextArrivalEntry: ArrivalComplicationEntry {}

// MARK: - Widget

struct SFTransitComplicationWidget: Widget {
    let kind = "SFTransitNextArrival"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextArrivalProvider()) { entry in
            ArrivalComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Next Arrival")
        .description("Your morning and afternoon commute stop, switching at noon.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

@main
struct SFTransitWidgetBundle: WidgetBundle {
    var body: some Widget {
        SFTransitComplicationWidget()
        NearbyFavoritesWidget()
    }
}
