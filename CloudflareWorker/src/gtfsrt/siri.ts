import type { Visit } from "./indexBuilder";

export function isoFromEpoch(epochSeconds: number): string {
  return new Date(epochSeconds * 1000).toISOString();
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
