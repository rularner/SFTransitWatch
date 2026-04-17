import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct NextArrivalEntry: TimelineEntry {
    let date: Date
    let stopName: String
    let route: String
    let minutesAway: Int
    let isConfigured: Bool
}

// MARK: - Timeline Provider

struct NextArrivalProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextArrivalEntry {
        NextArrivalEntry(date: .now, stopName: "Market & 4th", route: "38", minutesAway: 4, isConfigured: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextArrivalEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextArrivalEntry>) -> Void) {
        let sharedDefaults = UserDefaults(suiteName: "group.org.larner.SFTransitWatch") ?? .standard
        let apiKey = sharedDefaults.string(forKey: "511_API_KEY") ?? ""
        let stopName = sharedDefaults.string(forKey: "complication_stop_name") ?? ""
        let route = sharedDefaults.string(forKey: "complication_route") ?? ""
        let minutesAway = sharedDefaults.integer(forKey: "complication_minutes_away")

        guard !apiKey.isEmpty, !stopName.isEmpty else {
            let entry = NextArrivalEntry(date: .now, stopName: "", route: "", minutesAway: 0, isConfigured: false)
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(300))))
            return
        }

        let entry = NextArrivalEntry(
            date: .now,
            stopName: stopName,
            route: route,
            minutesAway: minutesAway,
            isConfigured: true
        )
        // Refresh every 5 minutes
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(300))))
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
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            case .accessoryCorner:
                cornerView
            default:
                circularView
            }
        }
    }

    private var unconfiguredView: some View {
        Image(systemName: "bus")
            .foregroundStyle(.secondary)
    }

    private var circularView: some View {
        VStack(spacing: 0) {
            Text(entry.route)
                .font(.system(size: 14, weight: .bold))
                .minimumScaleFactor(0.7)
            Text(entry.minutesAway == 0 ? "Now" : "\(entry.minutesAway)m")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(entry.minutesAway <= 2 ? .red : .primary)
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
                    .foregroundStyle(entry.minutesAway <= 2 ? .red : .primary)
            }
            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var cornerView: some View {
        Text(entry.minutesAway == 0 ? "Now" : "\(entry.minutesAway)m")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(entry.minutesAway <= 2 ? .red : .primary)
            .widgetLabel(entry.route)
            .containerBackground(.fill.tertiary, for: .widget)
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
        .description("Shows the next bus arrival for your top favorited stop.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}
