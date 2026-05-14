import WidgetKit
import SwiftUI
import SFTransitWatchPackage
import CoreLocation

// MARK: - Timeline Entry

struct NearbyFavoritesEntry: TimelineEntry {
    let date: Date
    let stopName: String
    let route: String
    let minutesAway: Int
    let isConfigured: Bool

    static let placeholder = NearbyFavoritesEntry(
        date: .now,
        stopName: "Market & 4th",
        route: "38",
        minutesAway: 4,
        isConfigured: true
    )

    static let unconfigured = NearbyFavoritesEntry(
        date: .now,
        stopName: "",
        route: "",
        minutesAway: 0,
        isConfigured: false
    )
}

// MARK: - Shared snapshot read

private enum NearbyFavoritesSnapshotStore {
    static let defaults = UserDefaults(suiteName: CommuteSlotsManager.appGroupSuiteName) ?? .standard

    static func snapshot(at date: Date) -> NearbyFavoritesEntry {
        let stopName = defaults.string(forKey: ComplicationUpdater.StorageKey.nearbyStopName) ?? ""
        let route = defaults.string(forKey: ComplicationUpdater.StorageKey.nearbyRoute) ?? ""
        let minutesAway = defaults.integer(forKey: ComplicationUpdater.StorageKey.nearbyMinutesAway)

        guard !stopName.isEmpty else { return .unconfigured }

        return NearbyFavoritesEntry(
            date: date,
            stopName: stopName,
            route: route,
            minutesAway: minutesAway,
            isConfigured: true
        )
    }
}

// MARK: - Timeline Provider

struct NearbyFavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearbyFavoritesEntry {
        NearbyFavoritesEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NearbyFavoritesEntry) -> Void) {
        completion(NearbyFavoritesSnapshotStore.snapshot(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyFavoritesEntry>) -> Void) {
        let now = Date.now
        var entries: [NearbyFavoritesEntry] = [NearbyFavoritesSnapshotStore.snapshot(at: now)]

        if let boundary = NextArrivalProvider.nextSlotBoundary(after: now) {
            entries.append(NearbyFavoritesSnapshotStore.snapshot(at: boundary))
        }

        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }
}

// MARK: - Views

struct NearbyFavoritesEntryView: View {
    var entry: NearbyFavoritesEntry
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

struct NearbyFavoritesWidget: Widget {
    let kind = "SFTransitNearbyFavorites"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NearbyFavoritesProvider()) { entry in
            NearbyFavoritesEntryView(entry: entry)
        }
        .configurationDisplayName("Nearby Favorite")
        .description("Your closest favorite stop's next arrival.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}
