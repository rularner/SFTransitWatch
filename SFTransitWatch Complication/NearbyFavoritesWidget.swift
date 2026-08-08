import SFTransitWatchPackage
import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct NearbyFavoritesEntry: TimelineEntry {
    let date: Date
    let stopName: String
    let route: String
    let arrivalTime: Date?
    let isConfigured: Bool

    static let placeholder = NearbyFavoritesEntry(
        date: .now,
        stopName: "Market & 4th",
        route: "38",
        arrivalTime: Date().addingTimeInterval(4 * 60),
        isConfigured: true
    )

    static let unconfigured = NearbyFavoritesEntry(
        date: .now,
        stopName: "",
        route: "",
        arrivalTime: nil,
        isConfigured: false
    )
}

// MARK: - Shared snapshot read

private enum NearbyFavoritesSnapshotStore {
    static let defaults = UserDefaults(suiteName: CommuteSlotsManager.appGroupSuiteName) ?? .standard

    static func snapshot(at date: Date) -> NearbyFavoritesEntry {
        let stopName = defaults.string(forKey: ComplicationUpdater.StorageKey.nearbyStopName) ?? ""
        let route = defaults.string(forKey: ComplicationUpdater.StorageKey.nearbyRoute) ?? ""
        let arrivalTime = defaults.object(forKey: ComplicationUpdater.StorageKey.nearbyArrivalTime) as? Date

        guard !stopName.isEmpty else { return .unconfigured }

        return NearbyFavoritesEntry(
            date: date,
            stopName: stopName,
            route: route,
            arrivalTime: arrivalTime,
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

extension NearbyFavoritesEntry: ArrivalComplicationEntry {}

// MARK: - Widget

struct NearbyFavoritesWidget: Widget {
    let kind = "SFTransitNearbyFavorites"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NearbyFavoritesProvider()) { entry in
            ArrivalComplicationEntryView(entry: entry)
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
