import type { Visit } from "./indexBuilder";

export function isoFromEpoch(epochSeconds: number): string {
  // Emit the same second-precision ISO8601 the real 511 SIRI feed uses (e.g.
  // "2026-01-01T10:25:00Z"), NOT Date.toISOString()'s ".000Z" millisecond form.
  // The app parses this response with the exact ISO8601DateFormatter it uses for
  // upstream 511, so the GTFS-RT translation must be byte-compatible — a fractional
  // ".000Z" makes that formatter return nil and silently drops every arrival.
  return new Date(Math.round(epochSeconds) * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function toStopMonitoringJson(args: {
  stopCode: string;
  visits: Visit[];
  maxOnward: number;
  stopName: (stopId: string) => string;
}): object {
  const nowIso = new Date().toISOString();
  const monitoredStopVisit = args.visits.map((v) => ({
    RecordedAtTime: nowIso,
    MonitoringRef: args.stopCode,
    MonitoredVehicleJourney: {
      LineRef: v.lineRef,
      DirectionRef: v.directionRef,
      OperatorRef: "SF",
      VehicleRef: v.vehicleRef ?? "",
      MonitoredCall: {
        StopPointRef: args.stopCode,
        ExpectedArrivalTime: isoFromEpoch(v.expectedArrival),
        AimedArrivalTime: isoFromEpoch(v.expectedArrival),
      },
      OnwardCalls: {
        OnwardCall: v.onward.slice(0, args.maxOnward).map((o) => ({
          StopPointRef: o.stopId,
          StopPointName: args.stopName(o.stopId),
          ExpectedArrivalTime: isoFromEpoch(o.time),
        })),
      },
    },
  }));
  return {
    ServiceDelivery: {
      ResponseTimestamp: nowIso,
      ProducerRef: "SF",
      Status: true,
      StopMonitoringDelivery: {
        version: "1.4",
        ResponseTimestamp: nowIso,
        Status: true,
        MonitoredStopVisit: monitoredStopVisit,
      },
    },
  };
}
