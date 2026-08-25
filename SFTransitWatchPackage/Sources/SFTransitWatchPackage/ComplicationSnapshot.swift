import Foundation

/// Pure decision logic for whether a complication write should also trigger
/// `WidgetCenter.reloadAllTimelines()`.
///
/// Reloading on every poll — even when nothing displayed would change — burns
/// through WidgetKit's per-app timeline-reload budget. Once that budget is
/// exhausted the system silently stops honoring further reload requests for
/// the rest of the day, so the complication freezes on whatever it last
/// managed to render while the app itself keeps fetching fresh arrivals.
public enum ComplicationSnapshot {
    public static func hasChanged(
        existingRoute: String?,
        existingArrivalTime: Date?,
        newRoute: String,
        newArrivalTime: Date
    ) -> Bool {
        existingRoute != newRoute || existingArrivalTime != newArrivalTime
    }
}
