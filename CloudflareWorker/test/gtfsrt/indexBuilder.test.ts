import { describe, it, expect } from "vitest";
import { buildArrivalsIndex, splitAgency, directionRef } from "../../src/gtfsrt/indexBuilder";
import type { TripUpdateEntity } from "../../src/gtfsrt/decode";

describe("splitAgency", () => {
  it("splits agency prefix from line", () => {
    expect(splitAgency("SF:44")).toEqual({ agency: "SF", line: "44" });
    expect(splitAgency("AC:72M")).toEqual({ agency: "AC", line: "72M" });
  });
  it("treats an unprefixed route as no agency", () => {
    expect(splitAgency("44")).toEqual({ agency: "", line: "44" });
  });
});

describe("directionRef", () => {
  it("maps 1->IB, 0->OB, undefined->''", () => {
    expect(directionRef(1)).toBe("IB");
    expect(directionRef(0)).toBe("OB");
    expect(directionRef(undefined)).toBe("");
  });
});

describe("buildArrivalsIndex", () => {
  const entity: TripUpdateEntity = {
    tripId: "t1", routeId: "SF:44", directionId: 1, vehicleId: "8751",
    stopTimeUpdates: [
      { stopSequence: 10, stopId: "16393", arrivalTime: 200 },
      { stopSequence: 11, stopId: "16301", arrivalTime: 300 },
      { stopSequence: 12, stopId: "16304", arrivalTime: 400 },
    ],
  };

  it("indexes by agency then stopId with stripped line and onward chain", () => {
    const idx = buildArrivalsIndex([entity]);
    expect(idx["SF"]["16393"]).toEqual([
      { lineRef: "44", directionRef: "IB", vehicleRef: "8751", expectedArrival: 200,
        onward: [{ stopId: "16301", time: 300 }, { stopId: "16304", time: 400 }] },
    ]);
    // the last stop has no onward calls
    expect(idx["SF"]["16304"][0].onward).toEqual([]);
  });

  it("sorts visits at a stop by expectedArrival", () => {
    const later = { ...entity, tripId: "t2", stopTimeUpdates: [{ stopSequence: 5, stopId: "16393", arrivalTime: 100 }] };
    const idx = buildArrivalsIndex([entity, later]);
    expect(idx["SF"]["16393"].map(v => v.expectedArrival)).toEqual([100, 200]);
  });

  it("uses departureTime when arrivalTime is absent, and skips stops with neither", () => {
    const e = { ...entity, tripId: "t3", stopTimeUpdates: [
      { stopSequence: 1, stopId: "A", departureTime: 500 },
      { stopSequence: 2, stopId: "B" },
    ] };
    const idx = buildArrivalsIndex([e]);
    expect(idx["SF"]["A"][0].expectedArrival).toBe(500);
    expect(idx["SF"]["B"]).toBeUndefined();
  });

  it("caps onward stops at MAX_ONWARD_STOPS instead of the full remaining trip", () => {
    const manyStops: TripUpdateEntity = {
      tripId: "t4", routeId: "SF:1", directionId: 1, vehicleId: "9999",
      stopTimeUpdates: Array.from({ length: 25 }, (_, i) => ({
        stopSequence: i + 1,
        stopId: `stop-${i + 1}`,
        arrivalTime: 1000 + i * 60,
      })),
    };
    const idx = buildArrivalsIndex([manyStops]);
    // 25 stops total, so the first stop has 24 possible onward stops — must be capped.
    expect(idx["SF"]["stop-1"][0].onward.length).toBe(15);
    expect(idx["SF"]["stop-1"][0].onward[0]).toEqual({ stopId: "stop-2", time: 1060 });
    expect(idx["SF"]["stop-1"][0].onward[14]).toEqual({ stopId: "stop-16", time: 1000 + 15 * 60 });
    // A stop near the end of the trip has fewer than 15 remaining — must not pad or error.
    expect(idx["SF"]["stop-20"][0].onward.length).toBe(5);
  });
});
