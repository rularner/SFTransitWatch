import XCTest
import SFTransitWatchPackage
@testable import SFTransitWatch_Watch_App

/// Tests for TransitAPI data parsing with simple mock responses.
/// Focuses on verifying XML/JSON parsing works correctly.
final class TransitAPIParsingTests: XCTestCase {

    var api: TransitAPI!
    var mockSession: MockURLSession!

    @MainActor
    override func setUp() {
        super.setUp()
        api = TransitAPI()
        mockSession = MockURLSession()
        api.urlSession = mockSession

        // Set API key via ConfigurationManager (not UserDefaults)
        ConfigurationManager.shared.apiKey = "test-key"
    }

    @MainActor
    override func tearDown() {
        super.tearDown()
        ConfigurationManager.shared.apiKey = ""
        ConfigurationManager.shared.workerToken = ""
        ConfigurationManager.shared.workerBaseURL = ""
    }

    @MainActor
    func testParseArrivalsWithValidXML() async {
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
        XCTAssertEqual(arrivals[0].route, "38")
    }

    @MainActor
    func testParseArrivalsWithEmptyXML() async {
        let xml = "<ServiceDelivery></ServiceDelivery>".data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/StopMonitoring")!, data: xml)

        let arrivals = await api.fetchArrivals(for: "15552", agency: "SF")

        XCTAssertTrue(arrivals.isEmpty)
    }

    @MainActor
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

    @MainActor
    func testParseStopsWithEmptyXML() async {
        let xml = "<StopPlaces></StopPlaces>".data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let stops = await api.fetchNearbyStops(latitude: 37.7858, longitude: -122.4064)

        XCTAssertTrue(stops.isEmpty)
    }

    @MainActor
    func testSearchStopsByExactCode() async {
        let xml = """
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Castro Station</StopPlaceName>
            <Location><Latitude>37.762</Latitude><Longitude>-122.435</Longitude></Location>
          </StopPlace>
          <StopPlace>
            <StopPlaceRef>13000</StopPlaceRef>
            <StopPlaceName>Market St &amp; 8th St</StopPlaceName>
            <Location><Latitude>37.780</Latitude><Longitude>-122.410</Longitude></Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let results = await api.searchStops(query: "15552", agencies: ["SF"])

        XCTAssertNotNil(results)
        XCTAssertEqual(results?.count, 1)
        XCTAssertEqual(results?.first?.code, "15552")
        XCTAssertEqual(results?.first?.name, "Castro Station")
    }

    @MainActor
    func testSearchStopsByNameSubstring() async {
        let xml = """
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Castro Station</StopPlaceName>
            <Location><Latitude>37.762</Latitude><Longitude>-122.435</Longitude></Location>
          </StopPlace>
          <StopPlace>
            <StopPlaceRef>13000</StopPlaceRef>
            <StopPlaceName>Market St &amp; 8th St</StopPlaceName>
            <Location><Latitude>37.780</Latitude><Longitude>-122.410</Longitude></Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let results = await api.searchStops(query: "castro", agencies: ["SF"])

        XCTAssertEqual(results?.count, 1)
        XCTAssertEqual(results?.first?.name, "Castro Station")
    }

    @MainActor
    func testSearchStopsEmptyQueryMakesNoRequests() async {
        let results = await api.searchStops(query: "   ", agencies: ["SF"])

        XCTAssertEqual(results, [BusStop](), "Whitespace-only query must return [] immediately")
        XCTAssertEqual(mockSession.requestCount(), 0, "Must not fire any network request")
    }

    @MainActor
    func testSearchStopsMultiAgencyMakesTwoRequests() async {
        let xml = """
        <StopPlaces>
          <StopPlace>
            <StopPlaceRef>15552</StopPlaceRef>
            <StopPlaceName>Castro Station</StopPlaceName>
            <Location><Latitude>37.762</Latitude><Longitude>-122.435</Longitude></Location>
          </StopPlace>
        </StopPlaces>
        """.data(using: .utf8)!
        mockSession.setMockResponse(for: URL(string: "https://api.511.org/transit/Stops")!, data: xml)

        let results = await api.searchStops(query: "15552", agencies: ["SF", "BA"])

        XCTAssertEqual(mockSession.requestCount(), 2, "One request per agency")
        XCTAssertEqual(results?.count, 2)
    }

    @MainActor
    func testSearchStopsReturnsNilWhenAllAgenciesFail() async {
        mockSession.setMockError(for: URL(string: "https://api.511.org")!,
                                 error: URLError(.notConnectedToInternet))

        let results = await api.searchStops(query: "castro", agencies: ["SF"])

        XCTAssertNil(results, "Should return nil when all agency fetches fail")
    }

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
