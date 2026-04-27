import Foundation

/// A Bay Area transit operator known to the 511.org SIRI feeds.
///
/// `code` is the value we pass as the `agency` query param. Stop codes are
/// scoped per-agency — the same numeric `stopCode` on two different agencies
/// refers to two unrelated stops — so every `BusStop` we persist has to know
/// which operator it belongs to.
struct Agency: Hashable, Codable, Identifiable {
    let code: String
    let displayName: String
    /// 2-3 char tag for compact UI rows when more than one agency is enabled.
    let badge: String

    var id: String { code }

    static let muni        = Agency(code: "SF", displayName: "Muni",            badge: "MUNI")
    static let bart        = Agency(code: "BA", displayName: "BART",            badge: "BART")
    static let acTransit   = Agency(code: "AC", displayName: "AC Transit",      badge: "AC")
    static let caltrain    = Agency(code: "CT", displayName: "Caltrain",        badge: "CT")
    static let goldenGate  = Agency(code: "GG", displayName: "Golden Gate",     badge: "GG")
    static let samTrans    = Agency(code: "SM", displayName: "SamTrans",        badge: "SM")
    static let vta         = Agency(code: "SC", displayName: "VTA",             badge: "VTA")

    /// Order matters: it's the order shown in Settings.
    static let known: [Agency] = [.muni, .bart, .acTransit, .caltrain, .goldenGate, .samTrans, .vta]

    static func named(_ code: String) -> Agency? {
        known.first { $0.code == code }
    }
}

/// Parsing/formatting for the `enabled_agencies` UserDefault, which stores a
/// comma-separated list of 511 agency codes (e.g. "SF,BA"). Empty / missing
/// always falls back to Muni so we never query 511 with no agency.
enum EnabledAgencies {
    static let storageKey = "enabled_agencies"
    static let `default` = "SF"

    static func parse(_ stored: String) -> [String] {
        let codes = stored
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return codes.isEmpty ? [Self.default] : codes
    }

    static func format(_ codes: [String]) -> String {
        codes.joined(separator: ",")
    }

    /// First enabled agency, used as the implicit agency for stop codes the
    /// user types in by hand (where we have no other context).
    static func defaultAgency(_ stored: String) -> String {
        parse(stored).first ?? Self.default
    }
}
