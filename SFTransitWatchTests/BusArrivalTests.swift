import XCTest
import SFTransitWatchPackage

final class BusArrivalTests: XCTestCase {

    // MARK: - minutesAway

    func testMinutesAwayFiveMinutes() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(300),
                                 now: now)
        XCTAssertEqual(arrival.minutesAway, 5)
    }

    func testMinutesAwayDue() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(10),
                                 now: now)
        XCTAssertEqual(arrival.minutesAway, 0)
    }

    func testMinutesAwayNeverNegative() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(-120),
                                 now: now)
        XCTAssertGreaterThanOrEqual(arrival.minutesAway, 0)
    }

    // MARK: - minutesString

    func testMinutesStringDue() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(10),
                                 now: now)
        XCTAssertEqual(arrival.minutesString, "Due")
    }

    func testMinutesStringOneMinute() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(90),
                                 now: now)
        XCTAssertEqual(arrival.minutesString, "1 min")
    }

    func testMinutesStringMultiple() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(600),
                                 now: now)
        XCTAssertEqual(arrival.minutesString, "10 min")
    }

    // MARK: - timeString

    func testTimeStringNotEmpty() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(300),
                                 now: now)
        XCTAssertFalse(arrival.timeString.isEmpty)
    }

    // MARK: - isRealTime default

    func testDefaultIsRealTime() {
        let now = Date()
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(300),
                                 now: now)
        XCTAssertTrue(arrival.isRealTime)
    }

    func testScheduledFlag() {
        let now = Date()
        let arrival = BusArrival(route: "F", destination: "Wharf",
                                 arrivalTime: now.addingTimeInterval(300),
                                 isRealTime: false,
                                 now: now)
        XCTAssertFalse(arrival.isRealTime)
    }

    // Regression guard: if BusArrival.init ever stops honoring the injected
    // `now` (e.g. someone reverts to `arrivalTime.timeIntervalSinceNow`), the
    // calculation will be made against the real wall clock — which is decades
    // away from this fixed reference date — and these assertions will fail.
    func testInjectedNowIsRespected() {
        let frozen = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01 UTC
        let fiveMinLater = BusArrival(route: "X", destination: "Y",
                                      arrivalTime: frozen.addingTimeInterval(300),
                                      now: frozen)
        XCTAssertEqual(fiveMinLater.minutesAway, 5)

        let twoMinEarlier = BusArrival(route: "X", destination: "Y",
                                       arrivalTime: frozen.addingTimeInterval(-120),
                                       now: frozen)
        XCTAssertEqual(twoMinEarlier.minutesAway, 0)
    }

    // MARK: - OnwardStop

    func testOnwardStopMinutesAway() {
        let now = Date()
        let stop = OnwardStop(id: "15725", name: "Market St & 4th St",
                              arrivalTime: now.addingTimeInterval(300), now: now)
        XCTAssertEqual(stop.minutesAway, 5)
    }

    func testOnwardStopMinutesAwayNeverNegative() {
        let now = Date()
        let stop = OnwardStop(id: "15725", name: "Market St & 4th St",
                              arrivalTime: now.addingTimeInterval(-60), now: now)
        XCTAssertEqual(stop.minutesAway, 0)
    }

    func testOnwardStopMinutesStringDue() {
        let now = Date()
        let stop = OnwardStop(id: "15725", name: "Market St & 4th St",
                              arrivalTime: now.addingTimeInterval(10), now: now)
        XCTAssertEqual(stop.minutesString, "Due")
    }

    func testOnwardStopMinutesStringOneMinute() {
        let now = Date()
        let stop = OnwardStop(id: "15725", name: "Market St & 4th St",
                              arrivalTime: now.addingTimeInterval(90), now: now)
        XCTAssertEqual(stop.minutesString, "1 min")
    }

    func testOnwardStopMinutesStringMultiple() {
        let now = Date()
        let stop = OnwardStop(id: "15725", name: "Market St & 4th St",
                              arrivalTime: now.addingTimeInterval(600), now: now)
        XCTAssertEqual(stop.minutesString, "10 min")
    }

    func testOnwardStopTimeStringNotEmpty() {
        let stop = OnwardStop(id: "15725", name: "Market St & 4th St",
                              arrivalTime: Date().addingTimeInterval(300))
        XCTAssertFalse(stop.timeString.isEmpty)
    }

    // MARK: - onwardStops and vehicleRef

    func testOnwardStopsDefaultEmpty() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(300))
        XCTAssertTrue(arrival.onwardStops.isEmpty)
    }

    func testVehicleRefDefaultNil() {
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: Date().addingTimeInterval(300))
        XCTAssertNil(arrival.vehicleRef)
    }

    func testOnwardStopsPassedThrough() {
        let now = Date()
        let stops = [
            OnwardStop(id: "A", name: "Stop A", arrivalTime: now.addingTimeInterval(300), now: now),
            OnwardStop(id: "B", name: "Stop B", arrivalTime: now.addingTimeInterval(480), now: now),
        ]
        let arrival = BusArrival(route: "38", destination: "Downtown",
                                 arrivalTime: now.addingTimeInterval(300),
                                 vehicleRef: "SF:9999",
                                 onwardStops: stops,
                                 now: now)
        XCTAssertEqual(arrival.vehicleRef, "SF:9999")
        XCTAssertEqual(arrival.onwardStops.count, 2)
        XCTAssertEqual(arrival.onwardStops[0].id, "A")
        XCTAssertEqual(arrival.onwardStops[1].name, "Stop B")
    }

    // MARK: - TransitJSON OnwardCalls decoding

    func testDecodeArrivalsWithOnwardCalls() {
        let json = """
        {
          "ServiceDelivery": {
            "StopMonitoringDelivery": {
              "MonitoredStopVisit": [{
                "MonitoredVehicleJourney": {
                  "LineRef": "SF:38",
                  "DirectionRef": "Downtown",
                  "VehicleRef": "SF:1234",
                  "MonitoredCall": {
                    "ExpectedArrivalTime": "2026-01-01T10:25:00+00:00"
                  },
                  "OnwardCalls": {
                    "OnwardCall": [
                      {
                        "StopPointRef": "15725",
                        "StopPointName": "Market St & 4th St",
                        "ExpectedArrivalTime": "2026-01-01T10:30:00+00:00"
                      },
                      {
                        "StopPointRef": "15726",
                        "StopPointName": "Market St & 5th St",
                        "ExpectedArrivalTime": "2026-01-01T10:32:00+00:00"
                      }
                    ]
                  }
                }
              }]
            }
          }
        }
        """.data(using: .utf8)!

        let arrivals = TransitJSON.decodeArrivals(json)
        XCTAssertNotNil(arrivals)
        XCTAssertEqual(arrivals?.count, 1)
        XCTAssertEqual(arrivals?.first?.vehicleRef, "SF:1234")
        XCTAssertEqual(arrivals?.first?.onwardStops.count, 2)
        XCTAssertEqual(arrivals?.first?.onwardStops[0].id, "15725")
        XCTAssertEqual(arrivals?.first?.onwardStops[0].name, "Market St & 4th St")
        XCTAssertEqual(arrivals?.first?.onwardStops[1].id, "15726")
    }

    func testDecodeArrivalsWithSingleOnwardCall() {
        let json = """
        {
          "ServiceDelivery": {
            "StopMonitoringDelivery": {
              "MonitoredStopVisit": [{
                "MonitoredVehicleJourney": {
                  "LineRef": "SF:N",
                  "DirectionRef": "Judah",
                  "MonitoredCall": {
                    "ExpectedArrivalTime": "2026-01-01T10:25:00+00:00"
                  },
                  "OnwardCalls": {
                    "OnwardCall": {
                      "StopPointRef": "99999",
                      "StopPointName": "Ocean Beach",
                      "ExpectedArrivalTime": "2026-01-01T10:40:00+00:00"
                    }
                  }
                }
              }]
            }
          }
        }
        """.data(using: .utf8)!

        let arrivals = TransitJSON.decodeArrivals(json)
        XCTAssertEqual(arrivals?.first?.onwardStops.count, 1)
        XCTAssertEqual(arrivals?.first?.onwardStops[0].id, "99999")
    }

    func testDecodeArrivalsWithNoOnwardCalls() {
        let json = """
        {
          "ServiceDelivery": {
            "StopMonitoringDelivery": {
              "MonitoredStopVisit": [{
                "MonitoredVehicleJourney": {
                  "LineRef": "SF:38",
                  "DirectionRef": "Downtown",
                  "MonitoredCall": {
                    "ExpectedArrivalTime": "2026-01-01T10:25:00+00:00"
                  }
                }
              }]
            }
          }
        }
        """.data(using: .utf8)!

        let arrivals = TransitJSON.decodeArrivals(json)
        XCTAssertNotNil(arrivals)
        XCTAssertTrue(arrivals?.first?.onwardStops.isEmpty ?? false)
        XCTAssertNil(arrivals?.first?.vehicleRef)
        let buffered = Telemetry.shared.bufferedEventsForTesting
        XCTAssertTrue(buffered.contains(where: { $0.errorKind == "no_onward_calls" }),
                      "Expected a no_onward_calls telemetry event to be buffered")
    }

    func testDecodeArrivalsOnwardCallWithAimedTimeFallback() {
        let json = """
        {
          "ServiceDelivery": {
            "StopMonitoringDelivery": {
              "MonitoredStopVisit": [{
                "MonitoredVehicleJourney": {
                  "LineRef": "SF:38",
                  "DirectionRef": "Downtown",
                  "MonitoredCall": {
                    "ExpectedArrivalTime": "2026-01-01T10:25:00+00:00"
                  },
                  "OnwardCalls": {
                    "OnwardCall": {
                      "StopPointRef": "55555",
                      "StopPointName": "Ferry Building",
                      "AimedArrivalTime": "2026-01-01T10:45:00+00:00"
                    }
                  }
                }
              }]
            }
          }
        }
        """.data(using: .utf8)!

        let arrivals = TransitJSON.decodeArrivals(json)
        XCTAssertEqual(arrivals?.first?.onwardStops.count, 1)
        XCTAssertEqual(arrivals?.first?.onwardStops[0].id, "55555")
        XCTAssertEqual(arrivals?.first?.onwardStops[0].name, "Ferry Building")
    }

    func testBusArrivalRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stop = OnwardStop(id: "X", name: "Stop X",
                              arrivalTime: now.addingTimeInterval(300), now: now)
        let original = BusArrival(route: "N", destination: "Judah",
                                   arrivalTime: now.addingTimeInterval(120),
                                   vehicleRef: "SF:42",
                                   onwardStops: [stop],
                                   now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BusArrival.self, from: data)
        XCTAssertEqual(decoded.vehicleRef, "SF:42")
        XCTAssertEqual(decoded.onwardStops.count, 1)
        XCTAssertEqual(decoded.onwardStops[0].id, "X")
    }
}
