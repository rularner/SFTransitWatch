import Foundation

public enum APIError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
    case networkError
    case xmlParsingError
}

/// Public JSON decoders for the 511.org SIRI feeds. These hide the raw
/// Decodable shapes (which are noisy and not useful as API surface) and
/// return the app's own value types.
public enum TransitJSON {
    /// Extracts unique service-alert summaries from a raw SIRI XML payload.
    /// Used by the XML fallback path in both phone and watch TransitAPI.
    public static func parseSituationSummaries(from data: Data) -> [String] {
        SIRIXMLParser.parseRecords(
            data: data,
            entryElement: "PtSituationElement",
            fields: ["Summary"]
        )
        .compactMap { $0["Summary"] }
        .filter { !$0.isEmpty }
    }

    /// Cleans a raw SIRI LineRef for display.
    /// 511.org prefixes line IDs with an agency code: "CT:L_LOCAL" → "L LOCAL".
    /// Strips everything up to and including the first ":", then replaces "_" with " ".
    public static func cleanLineRef(_ lineRef: String) -> String {
        var s = lineRef
        if let i = s.firstIndex(of: ":") {
            s = String(s[s.index(after: i)...])
        }
        return s.replacingOccurrences(of: "_", with: " ")
    }
    /// Decodes a `/Stops` JSON payload into BusStops. Returns nil if the
    /// payload doesn't decode (caller can fall back to XML parsing). The
    /// `agency` arg tags every returned stop, since stop codes are scoped.
    public static func decodeStops(_ data: Data, agency: String) -> [BusStop]? {
        guard let payload = try? JSONDecoder().decode(StopsResponse.self, from: data) else {
            return nil
        }
        return payload.contents.dataObjects.scheduledStopPoints.compactMap { point in
            guard
                let latitude = Double(point.location.latitude),
                let longitude = Double(point.location.longitude)
            else { return nil }
            return BusStop(
                id: point.id,
                name: point.name,
                code: point.id,
                latitude: latitude,
                longitude: longitude,
                routes: [],
                agency: agency
            )
        }
    }

    /// Decodes a SIRI `/StopTimetable` response into BusArrivals with `isRealTime: false`.
    /// Returns nil if the payload doesn't decode; returns [] if it decodes but has no visits.
    public static func decodeScheduledDepartures(_ data: Data) -> [BusArrival]? {
        guard let payload = try? JSONDecoder().decode(StopTimetableResponse.self, from: data) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        return payload.siri.serviceDelivery.stopTimetableDelivery.timetabledStopVisit.compactMap { visit in
            let journey = visit.targetedVehicleJourney
            let rawTime = journey.targetedCall.aimedArrivalTime ?? journey.targetedCall.aimedDepartureTime
            guard let rawTime, let arrivalTime = formatter.date(from: rawTime) else { return nil }
            let destination = journey.targetedCall.destinationDisplay
                ?? journey.vehicleJourneyName
                ?? journey.directionRef
            return BusArrival(
                route: cleanLineRef(journey.lineRef),
                destination: destination,
                arrivalTime: arrivalTime,
                isRealTime: false
            )
        }
    }

    /// Decodes a `/StopMonitoring` JSON payload into BusArrivals.
    /// Returns nil if it doesn't decode.
    public static func decodeArrivals(_ data: Data) -> [BusArrival]? {
        guard let payload = try? JSONDecoder().decode(StopMonitoringResponse.self, from: data) else {
            return nil
        }

        // Build situation number → summary lookup from the optional SituationExchangeDelivery.
        let situations: [String: String] = payload.serviceDelivery
            .situationExchangeDelivery?
            .situations
            .reduce(into: [:]) { dict, elem in
                if !elem.situationNumber.isEmpty, !elem.summary.isEmpty {
                    dict[elem.situationNumber] = elem.summary
                }
            } ?? [:]

        let formatter = ISO8601DateFormatter()
        let arrivals = payload.serviceDelivery.stopMonitoringDelivery.monitoredStopVisit.compactMap { visit -> BusArrival? in
            let journey = visit.monitoredVehicleJourney
            let call = journey.monitoredCall
            let rawTime =
                call.expectedArrivalTime ??
                call.expectedDepartureTime ??
                call.aimedArrivalTime ??
                call.aimedDepartureTime
            guard
                let rawTime,
                let arrivalTime = formatter.date(from: rawTime)
            else { return nil }

            let alerts = (call.situationRefs ?? []).compactMap { situations[$0] }

            let onwardStops: [OnwardStop] = journey.onwardCalls.compactMap { oc in
                let rawOcTime = oc.expectedArrivalTime
                    ?? oc.expectedDepartureTime
                    ?? oc.aimedArrivalTime
                    ?? oc.aimedDepartureTime
                guard let rawOcTime, let ocTime = formatter.date(from: rawOcTime) else { return nil }
                return OnwardStop(id: oc.stopPointRef, name: oc.stopPointName, arrivalTime: ocTime)
            }

            return BusArrival(
                route: Self.cleanLineRef(journey.lineRef),
                destination: journey.directionRef,
                arrivalTime: arrivalTime,
                isRealTime: true,
                alerts: alerts,
                vehicleRef: journey.vehicleRef,
                onwardStops: onwardStops
            )
        }

        if !arrivals.isEmpty && arrivals.allSatisfy({ $0.onwardStops.isEmpty }) {
            Telemetry.shared.logFetchError(
                endpoint: "StopMonitoring",
                errorKind: "no_onward_calls",
                httpStatus: nil,
                latencyMs: 0
            )
        }

        return arrivals
    }
}

// MARK: - Internal Decodable shapes

struct StopsResponse: Decodable {
    let contents: StopsContents

    enum CodingKeys: String, CodingKey {
        case contents = "Contents"
    }
}

struct StopsContents: Decodable {
    let dataObjects: StopsDataObjects
}

struct StopsDataObjects: Decodable {
    let scheduledStopPoints: [ScheduledStopPoint]

    enum CodingKeys: String, CodingKey {
        case scheduledStopPoints = "ScheduledStopPoint"
    }
}

struct ScheduledStopPoint: Decodable {
    let id: String
    let name: String
    let location: StopLocation

    enum CodingKeys: String, CodingKey {
        case id
        case name = "Name"
        case location = "Location"
    }
}

struct StopLocation: Decodable {
    let longitude: String
    let latitude: String

    enum CodingKeys: String, CodingKey {
        case longitude = "Longitude"
        case latitude = "Latitude"
    }
}

struct StopMonitoringResponse: Decodable {
    let serviceDelivery: StopMonitoringServiceDelivery

    enum CodingKeys: String, CodingKey {
        case serviceDelivery = "ServiceDelivery"
    }
}

struct StopMonitoringServiceDelivery: Decodable {
    let stopMonitoringDelivery: StopMonitoringDelivery
    let situationExchangeDelivery: SituationExchangeDelivery?

    enum CodingKeys: String, CodingKey {
        case stopMonitoringDelivery = "StopMonitoringDelivery"
        case situationExchangeDelivery = "SituationExchangeDelivery"
    }
}

struct StopMonitoringDelivery: Decodable {
    let monitoredStopVisit: [MonitoredStopVisit]

    enum CodingKeys: String, CodingKey {
        case monitoredStopVisit = "MonitoredStopVisit"
    }
}

struct MonitoredStopVisit: Decodable {
    let monitoredVehicleJourney: MonitoredVehicleJourney

    enum CodingKeys: String, CodingKey {
        case monitoredVehicleJourney = "MonitoredVehicleJourney"
    }
}

struct MonitoredVehicleJourney: Decodable {
    let lineRef: String
    let directionRef: String
    let vehicleRef: String?
    let monitoredCall: MonitoredCall
    let onwardCalls: [OnwardCall]

    enum CodingKeys: String, CodingKey {
        case lineRef       = "LineRef"
        case directionRef  = "DirectionRef"
        case vehicleRef    = "VehicleRef"
        case monitoredCall = "MonitoredCall"
        case onwardCalls   = "OnwardCalls"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineRef       = try  c.decode(String.self,        forKey: .lineRef)
        directionRef  = try  c.decode(String.self,        forKey: .directionRef)
        vehicleRef    = try? c.decodeIfPresent(String.self, forKey: .vehicleRef)
        monitoredCall = try  c.decode(MonitoredCall.self, forKey: .monitoredCall)
        if let wrapper = try? c.decodeIfPresent(OnwardCallsWrapper.self, forKey: .onwardCalls) {
            onwardCalls = wrapper.calls
        } else {
            onwardCalls = []
        }
    }
}

struct MonitoredCall: Decodable {
    let expectedArrivalTime: String?
    let expectedDepartureTime: String?
    let aimedArrivalTime: String?
    let aimedDepartureTime: String?
    /// Situation numbers referenced by this call; resolved against SituationExchangeDelivery.
    let situationRefs: [String]?

    enum CodingKeys: String, CodingKey {
        case expectedArrivalTime = "ExpectedArrivalTime"
        case expectedDepartureTime = "ExpectedDepartureTime"
        case aimedArrivalTime = "AimedArrivalTime"
        case aimedDepartureTime = "AimedDepartureTime"
        case situationRef = "SituationRef"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expectedArrivalTime   = try? c.decodeIfPresent(String.self, forKey: .expectedArrivalTime)
        expectedDepartureTime = try? c.decodeIfPresent(String.self, forKey: .expectedDepartureTime)
        aimedArrivalTime      = try? c.decodeIfPresent(String.self, forKey: .aimedArrivalTime)
        aimedDepartureTime    = try? c.decodeIfPresent(String.self, forKey: .aimedDepartureTime)
        // SituationRef may be absent, a single object, or an array.
        if let arr = try? c.decodeIfPresent([SituationRef].self, forKey: .situationRef) {
            situationRefs = arr.map(\.situationSimpleRef)
        } else if let single = try? c.decodeIfPresent(SituationRef.self, forKey: .situationRef) {
            situationRefs = [single.situationSimpleRef]
        } else {
            situationRefs = nil
        }
    }
}

struct SituationRef: Decodable {
    let situationSimpleRef: String
    enum CodingKeys: String, CodingKey { case situationSimpleRef = "SituationSimpleRef" }
}

struct SituationExchangeDelivery: Decodable {
    let situations: [PtSituationElement]

    enum CodingKeys: String, CodingKey { case ptSituationElement = "PtSituationElement" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        situations = (try? c.decodeIfPresent([PtSituationElement].self, forKey: .ptSituationElement)) ?? []
    }
}

struct PtSituationElement: Decodable {
    let situationNumber: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case situationNumber = "SituationNumber"
        case summary = "Summary"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        situationNumber = (try? c.decode(String.self, forKey: .situationNumber)) ?? ""
        // 511.org returns Summary as either a plain string or [{value, lang}].
        if let arr = try? c.decode([SituationText].self, forKey: .summary) {
            summary = arr.first(where: { $0.lang == "en" })?.value ?? arr.first?.value ?? ""
        } else {
            summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        }
    }
}

struct SituationText: Decodable {
    let value: String
    let lang: String?
}

struct OnwardCallsWrapper: Decodable {
    let calls: [OnwardCall]

    enum CodingKeys: String, CodingKey { case onwardCall = "OnwardCall" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decodeIfPresent([OnwardCall].self, forKey: .onwardCall) {
            calls = arr
        } else if let single = try? c.decodeIfPresent(OnwardCall.self, forKey: .onwardCall) {
            calls = [single]
        } else {
            calls = []
        }
    }
}

struct OnwardCall: Decodable {
    let stopPointRef: String
    let stopPointName: String
    let expectedArrivalTime: String?
    let expectedDepartureTime: String?
    let aimedArrivalTime: String?
    let aimedDepartureTime: String?

    enum CodingKeys: String, CodingKey {
        case stopPointRef          = "StopPointRef"
        case stopPointName         = "StopPointName"
        case expectedArrivalTime   = "ExpectedArrivalTime"
        case expectedDepartureTime = "ExpectedDepartureTime"
        case aimedArrivalTime      = "AimedArrivalTime"
        case aimedDepartureTime    = "AimedDepartureTime"
    }
}

// MARK: - Stop Timetable shapes

struct StopTimetableResponse: Decodable {
    let siri: StopTimetableSiri
    enum CodingKeys: String, CodingKey { case siri = "Siri" }
}

struct StopTimetableSiri: Decodable {
    let serviceDelivery: StopTimetableServiceDelivery
    enum CodingKeys: String, CodingKey { case serviceDelivery = "ServiceDelivery" }
}

struct StopTimetableServiceDelivery: Decodable {
    let stopTimetableDelivery: StopTimetableDelivery
    enum CodingKeys: String, CodingKey { case stopTimetableDelivery = "StopTimetableDelivery" }
}

struct StopTimetableDelivery: Decodable {
    let timetabledStopVisit: [TimetabledStopVisit]
    enum CodingKeys: String, CodingKey { case timetabledStopVisit = "TimetabledStopVisit" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decodeIfPresent([TimetabledStopVisit].self, forKey: .timetabledStopVisit) {
            timetabledStopVisit = arr
        } else if let single = try? c.decodeIfPresent(TimetabledStopVisit.self, forKey: .timetabledStopVisit) {
            timetabledStopVisit = [single]
        } else {
            timetabledStopVisit = []
        }
    }
}

struct TimetabledStopVisit: Decodable {
    let targetedVehicleJourney: TargetedVehicleJourney
    enum CodingKeys: String, CodingKey { case targetedVehicleJourney = "TargetedVehicleJourney" }
}

struct TargetedVehicleJourney: Decodable {
    let lineRef: String
    let directionRef: String
    let vehicleJourneyName: String?
    let targetedCall: TargetedCall
    enum CodingKeys: String, CodingKey {
        case lineRef            = "LineRef"
        case directionRef       = "DirectionRef"
        case vehicleJourneyName = "VehicleJourneyName"
        case targetedCall       = "TargetedCall"
    }
}

struct TargetedCall: Decodable {
    let aimedArrivalTime: String?
    let aimedDepartureTime: String?
    let destinationDisplay: String?
    enum CodingKeys: String, CodingKey {
        case aimedArrivalTime   = "AimedArrivalTime"
        case aimedDepartureTime = "AimedDepartureTime"
        case destinationDisplay = "DestinationDisplay"
    }
}
