import AppIntents
import SFTransitWatchPackage
import SwiftUI
import WatchKit

// MARK: - Agency Choice

enum TransitAgencyChoice: String, AppEnum, CaseIterable, Sendable {
    case muni = "SF"
    case bart = "BA"
    case acTransit = "AC"
    case caltrain = "CT"
    case goldenGate = "GG"
    case samTrans = "SM"
    case vta = "SC"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transit Agency"
    static let caseDisplayRepresentations: [TransitAgencyChoice: DisplayRepresentation] = [
        .muni: "Muni",
        .bart: "BART",
        .acTransit: "AC Transit",
        .caltrain: "Caltrain",
        .goldenGate: "Golden Gate",
        .samTrans: "SamTrans",
        .vta: "VTA"
    ]

    var displayName: String {
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

// MARK: - Check Nearby Stops Intent

struct CheckNearbyStopsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Nearby Stops"
    static let description = IntentDescription("Shows transit stops near your current location.")
    static let openAppWhenRun = true

    @Parameter(title: "Agency")
    var agency: TransitAgencyChoice?

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(agency?.rawValue ?? "", forKey: Agency.selectedAgencyKey)
        return .result()
    }
}

// MARK: - Check Stop Arrivals Intent

struct CheckStopArrivalsIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Bus Times"
    static let description = IntentDescription("Shows upcoming arrivals for a stop.")
    static let openAppWhenRun = true

    @Parameter(title: "Stop Name")
    var stopName: String?

    @Parameter(title: "Agency")
    var agency: TransitAgencyChoice?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(agency?.rawValue ?? "", forKey: Agency.selectedAgencyKey)

        let key = ConfigurationManager.shared.apiKey
        guard !key.isEmpty else {
            return .result(dialog: "Please configure your 511.org API key in SF Transit Watch settings.")
        }

        let prefix = agency.map { "\($0.displayName) " } ?? ""
        if let name = stopName {
            return .result(dialog: "Opening \(prefix)arrivals for \(name) in SF Transit Watch.")
        }
        return .result(dialog: "Opening SF Transit Watch to show nearby \(prefix)arrivals.")
    }
}

// MARK: - App Shortcuts Provider

struct SFTransitAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckNearbyStopsIntent(),
            phrases: [
                "Find nearby stops in \(.applicationName)",
                "Find nearby \(\.$agency) stops in \(.applicationName)",
                "Show nearby bus stops in \(.applicationName)",
                "Show nearby \(\.$agency) in \(.applicationName)",
                "Nearby transit in \(.applicationName)",
                "Nearby \(\.$agency) in \(.applicationName)"
            ],
            shortTitle: "Nearby Stops",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: CheckStopArrivalsIntent(),
            phrases: [
                "Check bus times in \(.applicationName)",
                "Check \(\.$agency) times in \(.applicationName)",
                "Show arrivals in \(.applicationName)",
                "Show \(\.$agency) arrivals in \(.applicationName)",
                "When is the next bus in \(.applicationName)",
                "When is the next \(\.$agency) in \(.applicationName)"
            ],
            shortTitle: "Bus Times",
            systemImageName: "bus.fill"
        )
    }
}
