import { describe, it, expect } from "vitest";
import { decodeTripUpdates } from "../../src/gtfsrt/decode";
import { writeVarint, writeField, writeLenField, writeStringField } from "../../src/gtfsrt/protobuf";

// Build a StopTimeEvent { time } (field 2, varint)
function stopTimeEvent(time: number): number[] {
  return writeField(2, 0, writeVarint(time));
}
// StopTimeUpdate { stop_sequence(1), arrival(2){time}, departure(3){time}, stop_id(4) }
// Field numbers match the real GTFS-RT spec (arrival=2, departure=3, stop_id=4).
function stu(seq: number, stopId: string, time: number): number[] {
  return [
    ...writeField(1, 0, writeVarint(seq)),
    ...writeLenField(2, stopTimeEvent(time)),
    ...writeStringField(4, stopId),
  ];
}
// TripDescriptor { trip_id(1), route_id(5), direction_id(6) }
function trip(tripId: string, routeId: string, dir: number): number[] {
  return [
    ...writeStringField(1, tripId),
    ...writeStringField(5, routeId),
    ...writeField(6, 0, writeVarint(dir)),
  ];
}
// TripUpdate { trip(1), stop_time_update(2)*, vehicle(3){id(1)} }
function tripUpdate(t: number[], stus: number[][], vehicleId: string): number[] {
  const parts = [...writeLenField(1, t)];
  for (const s of stus) parts.push(...writeLenField(2, s));
  parts.push(...writeLenField(3, writeStringField(1, vehicleId)));
  return parts;
}
// FeedEntity { trip_update(3) } ; FeedMessage { entity(2)* }
function feed(tripUpdates: number[][]): Uint8Array {
  const parts: number[] = [];
  for (const tu of tripUpdates) parts.push(...writeLenField(2, writeLenField(3, tu)));
  return new Uint8Array(parts);
}

describe("decodeTripUpdates", () => {
  it("decodes trip, route, direction, vehicle and stop times", () => {
    const bytes = feed([
      tripUpdate(trip("12053679", "SF:44", 1), [stu(10, "16393", 1783321088), stu(11, "16301", 1783321144)], "8751"),
    ]);
    const out = decodeTripUpdates(bytes);
    expect(out).toHaveLength(1);
    expect(out[0].tripId).toBe("12053679");
    expect(out[0].routeId).toBe("SF:44");
    expect(out[0].directionId).toBe(1);
    expect(out[0].vehicleId).toBe("8751");
    expect(out[0].stopTimeUpdates).toEqual([
      { stopSequence: 10, stopId: "16393", arrivalTime: 1783321088, departureTime: undefined },
      { stopSequence: 11, stopId: "16301", arrivalTime: 1783321144, departureTime: undefined },
    ]);
  });

  it("ignores non-trip_update entities and missing fields gracefully", () => {
    expect(decodeTripUpdates(new Uint8Array([]))).toEqual([]);
  });
});
