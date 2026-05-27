import Foundation

/// A Bay Area transit operator known to the 511.org SIRI feeds.
///
/// `code` is the value we pass as the `agency` query param. Stop codes are
/// scoped per-agency — the same numeric `stopCode` on two different agencies
/// refers to two unrelated stops — so every `BusStop` we persist has to know
/// which operator it belongs to.
public struct Agency: Hashable, Codable, Identifiable, Sendable {
    public let code: String
    public let displayName: String
    /// 2-3 char tag for compact UI rows when more than one agency is enabled.
    public let badge: String
    /// Radius in meters used when searching for nearby stops. Commuter rail
    /// agencies have widely spaced stations and need a much larger default.
    public let nearbyRadius: Int

    public var id: String { code }

    public init(code: String, displayName: String, badge: String, nearbyRadius: Int = 1_000) {
        self.code = code
        self.displayName = displayName
        self.badge = badge
        self.nearbyRadius = nearbyRadius
    }

    public static let muni        = Agency(code: "SF", displayName: "Muni",            badge: "MUNI", nearbyRadius: 1_000)
    public static let bart        = Agency(code: "BA", displayName: "BART",            badge: "BART", nearbyRadius: 1_500)
    public static let acTransit   = Agency(code: "AC", displayName: "AC Transit",      badge: "AC",   nearbyRadius: 1_000)
    public static let caltrain    = Agency(code: "CT", displayName: "Caltrain",        badge: "CT",   nearbyRadius: 10_000)
    public static let goldenGate  = Agency(code: "GG", displayName: "Golden Gate",     badge: "GG",   nearbyRadius: 10_000)
    public static let samTrans    = Agency(code: "SM", displayName: "SamTrans",        badge: "SM",   nearbyRadius: 3_000)
    public static let vta         = Agency(code: "SC", displayName: "VTA",             badge: "VTA",  nearbyRadius: 2_000)

    /// Order matters: it's the order shown in Settings.
    public static let known: [Agency] = [.muni, .bart, .acTransit, .caltrain, .goldenGate, .samTrans, .vta]

    public static func named(_ code: String) -> Agency? {
        known.first { $0.code == code }
    }

    /// UserDefault key for the single-agency filter set by voice intents and
    /// cleared from the in-app banner. Empty string means "no filter — use
    /// `enabled_agencies` as normal."
    public static let selectedAgencyKey = "selected_agency"
}

/// Parsing/formatting for the `enabled_agencies` UserDefault, which stores a
/// comma-separated list of 511 agency codes (e.g. "SF,BA"). Empty / missing
/// always falls back to Muni so we never query 511 with no agency.
public enum EnabledAgencies {
    public static let storageKey = "enabled_agencies"
    public static let `default`: String = Agency.known.map(\.code).joined(separator: ",")

    public static func parse(_ stored: String) -> [String] {
        let codes = stored
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return codes.isEmpty ? [Self.default] : codes
    }

    public static func format(_ codes: [String]) -> String {
        codes.joined(separator: ",")
    }

    /// First enabled agency, used as the implicit agency for stop codes the
    /// user types in by hand (where we have no other context).
    public static func defaultAgency(_ stored: String) -> String {
        parse(stored).first ?? Self.default
    }
}
