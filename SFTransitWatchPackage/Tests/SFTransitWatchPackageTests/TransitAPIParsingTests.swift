import XCTest
@testable import SFTransitWatchPackage

/// Tests for TransitAPI data parsing with simple mock responses.
/// Focuses on verifying XML/JSON parsing works correctly.
///
/// Migrated from the watch app's `TransitAPIParsingTests.swift`. Several tests from that
/// file were dropped here as exact (or near-exact, same-shape) duplicates of coverage
/// already ported into `TransitAPITests.swift` (Task 3) — see the migration report for
/// the full list.
@MainActor
final class TransitAPIParsingTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    override func setUp() async throws {
        try await super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession

        // Set API key via ConfigurationManager (not UserDefaults)
        ConfigurationManager.shared.apiKey = "test-key"
    }

    override func tearDown() async throws {
        try await super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
    }

    /// Regression: the SIRI-XML fallback parser (used in direct-511 mode,
    /// which the watch hits often) assigns `destination` from the raw
    /// DirectionRef field. It must map through directionLabel, same as the
    /// JSON decode path, so "IB"/"OB" never leak to the UI. Covers the "IB"
    /// side of the mapping; TransitAPITests.testParseArrivalsWithValidXMLMapsDirectionRefToOutbound
    /// (Task 3) covers the "OB" side.
    func testParseArrivalsWithValidXMLMapsDirectionRefToInbound() async {
        let isoDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ServiceDelivery>
          <StopMonitoringDelivery>
            <MonitoredStopVisit>
              <MonitoredVehicleJourney>
                <LineRef>38</LineRef>
                <DirectionRef>IB</DirectionRef>
                <MonitoredCall>
                  <ExpectedDepartureTime>\(isoDate)</ExpectedDepartureTime>
                </MonitoredCall>
              </MonitoredVehicleJourney>
            </MonitoredStopVisit>
          </StopMonitoringDelivery>
        </ServiceDelivery>
        """.data(using: .utf8)!

        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertFalse(arrivals.isEmpty)
        XCTAssertEqual(arrivals[0].destination, "Inbound")
    }

    /// Regression: the SIRI-XML fallback parser must accept any of the four
    /// SIRI time-field names (ExpectedArrivalTime, ExpectedDepartureTime,
    /// AimedArrivalTime, AimedDepartureTime), not just ExpectedDepartureTime.
    /// This mirrors the original hand-rolled regex's alternation before it
    /// was replaced by SIRIXMLParser, which initially only requested
    /// ExpectedDepartureTime and silently dropped records using the other
    /// three field names.
    func testParseArrivalsWithValidXMLUsingExpectedArrivalTime() async {
        let isoDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ServiceDelivery>
          <StopMonitoringDelivery>
            <MonitoredStopVisit>
              <MonitoredVehicleJourney>
                <LineRef>38</LineRef>
                <DirectionRef>IB</DirectionRef>
                <MonitoredCall>
                  <ExpectedArrivalTime>\(isoDate)</ExpectedArrivalTime>
                </MonitoredCall>
              </MonitoredVehicleJourney>
            </MonitoredStopVisit>
          </StopMonitoringDelivery>
        </ServiceDelivery>
        """.data(using: .utf8)!

        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertFalse(arrivals.isEmpty)
        XCTAssertEqual(arrivals[0].route, "38")
    }

    func testParseArrivalsWithValidXMLUsingAimedArrivalTime() async {
        let isoDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ServiceDelivery>
          <StopMonitoringDelivery>
            <MonitoredStopVisit>
              <MonitoredVehicleJourney>
                <LineRef>38</LineRef>
                <DirectionRef>IB</DirectionRef>
                <MonitoredCall>
                  <AimedArrivalTime>\(isoDate)</AimedArrivalTime>
                </MonitoredCall>
              </MonitoredVehicleJourney>
            </MonitoredStopVisit>
          </StopMonitoringDelivery>
        </ServiceDelivery>
        """.data(using: .utf8)!

        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertFalse(arrivals.isEmpty)
        XCTAssertEqual(arrivals[0].route, "38")
    }

    func testParseArrivalsWithValidXMLUsingAimedDepartureTime() async {
        let isoDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ServiceDelivery>
          <StopMonitoringDelivery>
            <MonitoredStopVisit>
              <MonitoredVehicleJourney>
                <LineRef>38</LineRef>
                <DirectionRef>IB</DirectionRef>
                <MonitoredCall>
                  <AimedDepartureTime>\(isoDate)</AimedDepartureTime>
                </MonitoredCall>
              </MonitoredVehicleJourney>
            </MonitoredStopVisit>
          </StopMonitoringDelivery>
        </ServiceDelivery>
        """.data(using: .utf8)!

        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertFalse(arrivals.isEmpty)
        XCTAssertEqual(arrivals[0].route, "38")
    }

    func testParseArrivalsWithEmptyXML() async {
        let xml = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
    }

    func testParseStopsWithValidXML() async {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Market St &amp; 4th St</StopPlaceName>
            <Location>
              <Latitude>37.7858</Latitude>
              <Longitude>-122.4064</Longitude>
            </Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!

        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let stops = await api.fetchNearbyStops(latitude: 37.7858, longitude: -122.4064)

        XCTAssertFalse(stops.isEmpty)
        XCTAssertEqual(stops[0].id, "15552")
    }

    func testParseStopsWithEmptyXML() async {
        let xml = "<StopPlaces></StopPlaces>".data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let stops = await api.fetchNearbyStops(latitude: 37.7858, longitude: -122.4064)

        XCTAssertTrue(stops.isEmpty)
    }

    // MARK: - TransitJSON.decodeScheduledDepartures

    func testDecodeScheduledDepartures_validPayload() {
        let isoIn5min = ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        let isoIn15min = ISO8601DateFormatter().string(from: Date().addingTimeInterval(900))
        let json = """
        {
          "Siri": {
            "ServiceDelivery": {
              "StopTimetableDelivery": {
                "TimetabledStopVisit": [
                  {
                    "MonitoringRef": "70021",
                    "TargetedVehicleJourney": {
                      "LineRef": "Local Weekday",
                      "DirectionRef": "N",
                      "VehicleJourneyName": "San Francisco",
                      "TargetedCall": {
                        "AimedArrivalTime": "\(isoIn5min)",
                        "DestinationDisplay": "San Francisco"
                      }
                    }
                  },
                  {
                    "MonitoringRef": "70021",
                    "TargetedVehicleJourney": {
                      "LineRef": "Limited Weekday",
                      "DirectionRef": "N",
                      "VehicleJourneyName": "San Francisco",
                      "TargetedCall": {
                        "AimedDepartureTime": "\(isoIn15min)",
                        "DestinationDisplay": "San Francisco"
                      }
                    }
                  }
                ]
              }
            }
          }
        }
        """.data(using: .utf8)!

        let arrivals = TransitJSON.decodeScheduledDepartures(json)

        XCTAssertNotNil(arrivals)
        XCTAssertEqual(arrivals?.count, 2)
        XCTAssertEqual(arrivals?[0].route, "Local Weekday")
        XCTAssertFalse(arrivals?[0].isRealTime ?? true, "Must be isRealTime: false")
        XCTAssertEqual(arrivals?[0].destination, "San Francisco")
        XCTAssertEqual(arrivals?[1].route, "Limited Weekday")
        XCTAssertFalse(arrivals?[1].isRealTime ?? true)
    }

    func testDecodeScheduledDepartures_emptyVisits() {
        let json = """
        {
          "Siri": {
            "ServiceDelivery": {
              "StopTimetableDelivery": {
                "TimetabledStopVisit": []
              }
            }
          }
        }
        """.data(using: .utf8)!

        let arrivals = TransitJSON.decodeScheduledDepartures(json)
        XCTAssertNotNil(arrivals)
        XCTAssertEqual(arrivals?.count, 0)
    }

    func testDecodeScheduledDepartures_malformedJSON() {
        let arrivals = TransitJSON.decodeScheduledDepartures("not json".data(using: .utf8)!)
        XCTAssertNil(arrivals)
    }

    func testDecodeScheduledDepartures_missingTime_skipsVisit() {
        let json = """
        {
          "Siri": {
            "ServiceDelivery": {
              "StopTimetableDelivery": {
                "TimetabledStopVisit": [
                  {
                    "MonitoringRef": "70021",
                    "TargetedVehicleJourney": {
                      "LineRef": "Local Weekday",
                      "DirectionRef": "N",
                      "TargetedCall": {}
                    }
                  }
                ]
              }
            }
          }
        }
        """.data(using: .utf8)!

        let arrivals = TransitJSON.decodeScheduledDepartures(json)
        XCTAssertNotNil(arrivals)
        XCTAssertEqual(arrivals?.count, 0, "Visit with no time must be skipped")
    }

    // MARK: - TransitJSON.decodeTimetableJourneyStops

    func testDecodeTimetableJourneyStops_returnsStopsAfterBoarding() {
        let now = Date()
        let cal = Calendar.current
        // Build times relative to now's HH:MM so the reconstruction logic finds them
        let boardingComponents = cal.dateComponents([.hour, .minute], from: now.addingTimeInterval(300))
        let h = boardingComponents.hour ?? 10
        let m = boardingComponents.minute ?? 5
        let pad = { (n: Int) in String(format: "%02d", n) }
        let t1 = "\(pad(h)):\(pad(m)):00"                                  // boarding stop time
        let t2 = "\(pad((h * 60 + m + 5) / 60 % 24)):\(pad((m + 5) % 60)):00"  // onward +5 min
        let t3 = "\(pad((h * 60 + m + 10) / 60 % 24)):\(pad((m + 10) % 60)):00" // onward +10 min

        let json = """
        {
          "Content": {
            "TimetableFrame": [{
              "Name": "38:IB:WEEKDAY",
              "vehicleJourneys": {
                "ServiceJourney": [{
                  "JourneyPatternView": { "DirectionRef": { "ref": "IB" } },
                  "calls": { "Call": [
                    {"ScheduledStopPointRef":{"ref":"15720"},"Arrival":{"Time":"\(t1)","DaysOffset":"0"},"Departure":{"Time":"\(t1)","DaysOffset":"0"},"order":"1"},
                    {"ScheduledStopPointRef":{"ref":"15725"},"Arrival":{"Time":"\(t1)","DaysOffset":"0"},"Departure":{"Time":"\(t1)","DaysOffset":"0"},"order":"2"},
                    {"ScheduledStopPointRef":{"ref":"15730"},"Arrival":{"Time":"\(t2)","DaysOffset":"0"},"Departure":{"Time":"\(t2)","DaysOffset":"0"},"order":"3"},
                    {"ScheduledStopPointRef":{"ref":"15735"},"Arrival":{"Time":"\(t3)","DaysOffset":"0"},"Departure":{"Time":"\(t3)","DaysOffset":"0"},"order":"4"}
                  ]},
                  "id": "trip-1"
                }]
              }
            }]
          }
        }
        """.data(using: .utf8)!

        let stops = TransitJSON.decodeTimetableJourneyStops(
            data: json,
            boardingStopId: "15725",
            boardingTime: now.addingTimeInterval(300)
        )

        XCTAssertNotNil(stops)
        XCTAssertEqual(stops?.count, 3, "boarding stop + 2 onward stops")
        XCTAssertEqual(stops?[0].id, "15725")
        XCTAssertEqual(stops?[1].id, "15730")
        XCTAssertEqual(stops?[2].id, "15735")
        XCTAssertFalse(stops?[0].isRealTime ?? true)
    }

    func testDecodeTimetableJourneyStops_noMatchingTrip_returnsEmpty() {
        let json = """
        {
          "Content": {
            "TimetableFrame": [{
              "Name": "38:IB:WEEKDAY",
              "vehicleJourneys": {
                "ServiceJourney": [{
                  "JourneyPatternView": { "DirectionRef": { "ref": "IB" } },
                  "calls": { "Call": [
                    {"ScheduledStopPointRef":{"ref":"15730"},"Arrival":{"Time":"10:00:00","DaysOffset":"0"},"Departure":{"Time":"10:00:00","DaysOffset":"0"},"order":"1"}
                  ]},
                  "id": "trip-1"
                }]
              }
            }]
          }
        }
        """.data(using: .utf8)!

        let stops = TransitJSON.decodeTimetableJourneyStops(
            data: json,
            boardingStopId: "99999",
            boardingTime: Date()
        )

        XCTAssertNotNil(stops)
        XCTAssertEqual(stops?.count, 0)
    }

    func testDecodeTimetableJourneyStops_malformedJSON_returnsNil() {
        let stops = TransitJSON.decodeTimetableJourneyStops(
            data: "bad".data(using: .utf8)!,
            boardingStopId: "15725",
            boardingTime: Date()
        )
        XCTAssertNil(stops)
    }
}
