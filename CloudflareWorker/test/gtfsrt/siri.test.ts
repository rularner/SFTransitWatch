import { describe, it, expect } from "vitest";
import { toStopMonitoringJson, isoFromEpoch } from "../../src/gtfsrt/siri";
import type { Visit } from "../../src/gtfsrt/indexBuilder";

const visit: Visit = {
  lineRef: "44", directionRef: "IB", vehicleRef: "8751", expectedArrival: 1783321246,
  onward: [{ stopId: "16301", time: 1783321300 }, { stopId: "16304", time: 1783321360 }],
};

describe("isoFromEpoch", () => {
  it("formats epoch seconds as second-precision ISO8601 UTC matching the 511 SIRI feed", () => {
    // No ".000Z" fraction — the app's ISO8601DateFormatter rejects fractional seconds.
    expect(isoFromEpoch(1783321246)).toBe("2026-07-06T07:00:46Z");
  });
});

describe("toStopMonitoringJson", () => {
  const json = toStopMonitoringJson({
    stopCode: "16393", visits: [visit], maxOnward: 1,
    stopName: (id) => (id === "16301" ? "Silver Ave" : id),
  }) as any;

  it("nests SIRI keys the client decoder expects", () => {
    const visitJson = json.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit[0];
    const mvj = visitJson.MonitoredVehicleJourney;
    expect(mvj.LineRef).toBe("44");
    expect(mvj.DirectionRef).toBe("IB");
    expect(mvj.VehicleRef).toBe("8751");
    expect(mvj.MonitoredCall.StopPointRef).toBe("16393");
    expect(mvj.MonitoredCall.ExpectedArrivalTime).toBe(isoFromEpoch(1783321246));
  });

  it("caps onward calls at maxOnward and resolves names", () => {
    const oc = json.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit[0]
      .MonitoredVehicleJourney.OnwardCalls.OnwardCall;
    expect(oc).toHaveLength(1);
    expect(oc[0].StopPointRef).toBe("16301");
    expect(oc[0].StopPointName).toBe("Silver Ave");
  });

  it("emits an empty MonitoredStopVisit array for no visits", () => {
    const empty = toStopMonitoringJson({ stopCode: "1", visits: [], maxOnward: 10, stopName: (id) => id }) as any;
    expect(empty.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit).toEqual([]);
  });
});
