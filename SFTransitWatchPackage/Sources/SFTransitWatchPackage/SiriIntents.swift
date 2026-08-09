import AppIntents
import CoreLocation
import SwiftUI

// MARK: - Agency Choice

public enum TransitAgencyChoice: String, AppEnum, CaseIterable, Sendable {
    case muni = "SF"
    case bart = "BA"
    case acTransit = "AC"
    case caltrain = "CT"
    case goldenGate = "GG"
    case samTrans = "SM"
    case vta = "SC"

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transit Agency"
    public static let caseDisplayRepresentations: [TransitAgencyChoice: DisplayRepresentation] = [
        .muni: "Muni",
        .bart: "BART",
        .acTransit: "AC Transit",
        .caltrain: "Caltrain",
        .goldenGate: "Golden Gate",
        .samTrans: "SamTrans",
        .vta: "VTA"
    ]

    public var displayName: String {
        switch self {
        case .muni: return "Muni"
        case .bart: return "BART"
        case .acTransit: return "AC Transit"
        case .caltrain: return "Caltrain"
        case .goldenGate: return "Golden Gate"
        case .samTrans: return "SamTrans"
        case .vta: return "VTA"
        }
    }
}

// MARK: - Shared Helpers

func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

/// `stops` must be non-empty — callers only invoke this after confirming there's at least
/// one favorite. Pure and separate from `perform()` so it's directly unit-testable.
func nearestFavorite(among stops: [BusStop], location: CLLocation) -> BusStop {
    stops.min { $0.distance(to: location) < $1.distance(to: location) }!
}

// MARK: - Check Nearby Stops Intent

public struct CheckNearbyStopsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Nearby Stops"
    public static let description = IntentDescription("Shows transit stops near your current location.")
    public static let openAppWhenRun = true

    @Parameter(title: "Agency")
    public var agency: TransitAgencyChoice?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        persistSelectedAgency(agency)
        return .result()
    }
}

@MainActor
func persistSelectedAgency(_ agency: TransitAgencyChoice?) {
    UserDefaults.standard.set(agency?.rawValue ?? "", forKey: Agency.selectedAgencyKey)
}

// MARK: - Check Stop Arrivals Intent

public struct CheckStopArrivalsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check Bus Times"
    public static let description = IntentDescription("Shows upcoming arrivals for a stop.")
    public static let openAppWhenRun = true

    @Parameter(title: "Stop Name")
    public var stopName: String?

    @Parameter(title: "Agency")
    public var agency: TransitAgencyChoice?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        persistSelectedAgency(agency)
        let text = Self.dialogText(agency: agency, stopName: stopName)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }

    @MainActor
    static func dialogText(agency: TransitAgencyChoice?, stopName: String?) -> String {
        // A worker-provisioned user has no 511 key but is fully configured, so gate on the
        // same predicate the rest of the app uses rather than the raw API key.
        guard ConfigurationManager.shared.isConfigured else {
            return "Please configure your 511.org API key in SF Transit Watch settings."
        }
        let prefix = agency.map { "\($0.displayName) " } ?? ""
        if let name = stopName {
            return "Opening \(prefix)arrivals for \(name) in SF Transit Watch."
        }
        return "Opening SF Transit Watch to show nearby \(prefix)arrivals."
    }
}

// MARK: - Check Favorite Arrival Intent

public struct CheckFavoriteArrivalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Bus for My Favorite Stop"
    public static let description = IntentDescription("Speaks the next arrivals at your nearest favorited stop.")
    public static let openAppWhenRun = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ConfigurationManager.shared.isConfigured else {
            return .result(dialog: IntentDialog(stringLiteral: "Please configure your 511.org API key in SF Transit Watch settings."))
        }

        let favorites = FavoritesManager.allFavorites()
        guard !favorites.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "You don't have any favorite stops yet. Add one in SF Transit Watch."))
        }

        let stop: BusStop
        if favorites.count == 1 {
            stop = favorites[0]
        } else {
            guard let location = await LocationManager().currentLocationOnce(timeout: 8) else {
                return .result(dialog: IntentDialog(stringLiteral: "Enable location access for SF Transit Watch to use this."))
            }
            stop = nearestFavorite(among: favorites, location: location)
        }

        let api = TransitAPI()
        guard let arrivals = await withTimeout(seconds: 8, operation: { await api.fetchArrivals(for: stop.id, agency: stop.agency) }) else {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't reach 511 right now, try again shortly."))
        }

        return .result(dialog: IntentDialog(stringLiteral: Self.arrivalsDialogText(stopName: stop.name, arrivals: arrivals)))
    }

    static func arrivalsDialogText(stopName: String, arrivals: [BusArrival]) -> String {
        let sorted = arrivals.sorted { $0.arrivalTime < $1.arrivalTime }
        guard let first = sorted.first else {
            return "No upcoming arrivals for \(stopName) right now."
        }
        if sorted.count == 1 {
            return "The \(first.route) arrives at \(stopName) in \(first.minutesAway) minutes."
        }
        let second = sorted[1]
        return "The \(first.route) arrives at \(stopName) in \(first.minutesAway) minutes, then \(second.minutesAway) minutes."
    }
}
