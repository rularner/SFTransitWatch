import SwiftUI
import WidgetKit

/// Common shape both `NextArrivalEntry` and `NearbyFavoritesEntry` already have.
protocol ArrivalComplicationEntry {
    var stopName: String { get }
    var route: String { get }
    var arrivalTime: Date? { get }
    var isConfigured: Bool { get }
}

struct ArrivalComplicationEntryView<Entry: ArrivalComplicationEntry>: View {
    var entry: Entry
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
            arrivalText
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
                arrivalText
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(imminenceTint)
            }
            Spacer()
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var cornerView: some View {
        arrivalText
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(imminenceTint)
            .widgetLabel(entry.route)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    private var inlineView: some View {
        Group {
            if let arrivalTime = entry.arrivalTime {
                let shortRoute = entry.route.split(separator: " ").first.map(String.init) ?? entry.route
                (Text(shortRoute + " ") + Text(arrivalTime, style: .relative))
                    .widgetAccentable()
            } else {
                Text(entry.route)
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder
    private var arrivalText: some View {
        if let arrivalTime = entry.arrivalTime {
            Text(arrivalTime, style: .relative)
        } else {
            Text("—")
        }
    }

    private var imminenceTint: Color {
        guard let arrivalTime = entry.arrivalTime else { return .primary }
        return arrivalTime.timeIntervalSinceNow <= 2 * 60 ? .red : .primary
    }
}
