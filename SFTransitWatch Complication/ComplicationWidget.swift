import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct NextArrivalEntry: TimelineEntry {
    let date: Date
    let slot: CommuteSlotsManager.Slot?
    let stopName: String
    let route: String
    let minutesAway: Int
    let isConfigured: Bool

    static let placeholder = NextArrivalEntry(
        date: .now,
        slot: .morning,
        stopName: "Market & 4th",
        route: "38",
        minutesAway: 4,
        isConfigured: true
    )

    static let unconfigured = NextArrivalEntry(
        date: .now,
        slot: nil,
        stopName: "",
        route: "",
        minutesAway: 0,
        isConfigured: false
    )
}

// MARK: - Shared snapshot read

private enum SnapshotStore {
    static let defaults = UserDefaults(suiteName: CommuteSlotsManager.appGroupSuiteName) ?? .standard

    static func snapshot(for slot: CommuteSlotsManager.Slot, at date: Date) -> NextArrivalEntry? {
        let stopName = defaults.string(forKey: ComplicationUpdater.StorageKey.stopName(slot)) ?? ""
        let route = defaults.string(forKey: ComplicationUpdater.StorageKey.route(slot)) ?? ""
        let minutesAway = defaults.integer(forKey: ComplicationUpdater.StorageKey.minutesAway(slot))
        let configuredStopId = defaults.string(forKey: slot.storageKey) ?? ""

        guard !configuredStopId.isEmpty, !stopName.isEmpty else { return nil }

        return NextArrivalEntry(
            date: date,
            slot: slot,
            stopName: stopName,
            route: route,
            minutesAway: minutesAway,
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
        return NextArrivalEntry(
            date: date,
            slot: nil,
            stopName: "",
            route: "",
            minutesAway: 0,
            isConfigured: false
        )
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

        // Reload every 5 minutes to pick up fresh minutesAway data written
        // by the watch app, and to refresh the slot choice.
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

struct ComplicationWidgetEntryView: View {
    var entry: NextArrivalEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if !entry.isConfigured {
            unconfiguredView
        } else {
            switch family {
            case .accessoryCircular:    circularView
            case .accessoryRectangular: rectangularView
            case .accessoryCorner:      cornerView
            case .accessoryInline:      inlineView
            default:                    circularView
            }
        }
    }

    private var unconfiguredView: some View {
        Image(systemName: "bus")
            .foregroundStyle(.secondary)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    private var circularView: some View {
        VStack(spacing: 0) {
            Text(entry.route)
                .font(.system(size: 14, weight: .bold))
                .minimumScaleFactor(0.7)
            Text(minutesLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(imminenceTint)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Text(entry.route)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.stopName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.minutesAway == 0 ? "Due now" : "\(entry.minutesAway) min")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(imminenceTint)
            }
            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var cornerView: some View {
        Text(minutesLabel)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(imminenceTint)
            .widgetLabel(entry.route)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    // Inline family: single horizontal line at the top of a face.
    // Rendered as "· 38 4m" so the route and ETA read as one phrase.
    private var inlineView: some View {
        Text("\(entry.route) \(minutesLabel)")
            .widgetAccentable()
    }

    private var minutesLabel: String {
        entry.minutesAway == 0 ? "Now" : "\(entry.minutesAway)m"
    }

    private var imminenceTint: Color {
        entry.minutesAway <= 2 ? .red : .primary
    }
}

// MARK: - Widget

@main
struct SFTransitComplicationWidget: Widget {
    let kind = "SFTransitNextArrival"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextArrivalProvider()) { entry in
            ComplicationWidgetEntryView(entry: entry)
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
