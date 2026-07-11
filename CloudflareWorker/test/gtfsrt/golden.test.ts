import { describe, it, expect } from "vitest";
import { decodeTripUpdates } from "../../src/gtfsrt/decode";
import { buildArrivalsIndex } from "../../src/gtfsrt/indexBuilder";
import { toStopMonitoringJson, isoFromEpoch } from "../../src/gtfsrt/siri";
import { writeVarint, writeField, writeLenField, writeStringField } from "../../src/gtfsrt/protobuf";

// Mirror the real capture: SF:44, direction_id 1 (=IB), stop 16393, arrival epoch E.
const E = 1783321246;
function stopTimeEvent(t: number) { return writeField(2, 0, writeVarint(t)); }
function stu(seq: number, id: string, t: number) {
  // Real GTFS-RT wire order: stop_sequence(1), arrival(2){time}, stop_id(4).
  return [...writeField(1, 0, writeVarint(seq)), ...writeLenField(2, stopTimeEvent(t)), ...writeStringField(4, id)];
}
const trip = [...writeStringField(1, "12074830"), ...writeStringField(5, "SF:44"), ...writeField(6, 0, writeVarint(1))];
const tu = [...writeLenField(1, trip), ...writeLenField(2, stu(10, "16393", E))];
const feed = new Uint8Array(writeLenField(2, writeLenField(3, tu)));

describe("golden transparency", () => {
  it("emits the same route/direction/time a client reads from real 511 SIRI", () => {
    const idx = buildArrivalsIndex(decodeTripUpdates(feed));
    const json = toStopMonitoringJson({ stopCode: "16393", visits: idx["SF"]["16393"], maxOnward: 10, stopName: (i) => i }) as any;
    const mvj = json.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit[0].MonitoredVehicleJourney;
    // Real 511 capture for 16393 showed LineRef "44", DirectionRef "IB".
    expect(mvj.LineRef).toBe("44");            // → BusArrival.route
    expect(mvj.DirectionRef).toBe("IB");       // → BusArrival.destination
    expect(mvj.MonitoredCall.ExpectedArrivalTime).toBe(isoFromEpoch(E)); // → arrival minute
  });
});
