import AppIntents
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
        let key = ConfigurationManager.shared.apiKey
        guard !key.isEmpty else {
            return "Please configure your 511.org API key in SF Transit Watch settings."
        }
        let prefix = agency.map { "\($0.displayName) " } ?? ""
        if let name = stopName {
            return "Opening \(prefix)arrivals for \(name) in SF Transit Watch."
        }
        return "Opening SF Transit Watch to show nearby \(prefix)arrivals."
    }
}
