import type { TripUpdateEntity } from "./decode";

export interface Visit {
  lineRef: string;
  directionRef: string;
  vehicleRef?: string;
  expectedArrival: number;
  onward: { stopId: string; time: number }[];
}
export type ArrivalsIndex = Record<string, Record<string, Visit[]>>;

// Every current client asks for at most 10 onward stops (phone hardcodes
// MaximumNumberOfCallsOnwards=10; watch omits the param and gets the worker's
// own default of 10 in snapshot.ts). toStopMonitoringJson truncates to the
// per-request value anyway (siri.ts), so computing the full remaining-trip
// onward list here is pure wasted CPU on every refresh. 15 leaves headroom
// above the only value any client actually sends.
const MAX_ONWARD_STOPS = 15;

export function splitAgency(routeId: string): { agency: string; line: string } {
  const i = routeId.indexOf(":");
  if (i === -1) return { agency: "", line: routeId };
  return { agency: routeId.slice(0, i), line: routeId.slice(i + 1) };
}

export function directionRef(directionId: number | undefined): string {
  if (directionId === 1) return "IB";
  if (directionId === 0) return "OB";
  return "";
}

export function buildArrivalsIndex(entities: TripUpdateEntity[]): ArrivalsIndex {
  const index: ArrivalsIndex = {};
  for (const e of entities) {
    const { agency, line } = splitAgency(e.routeId);
    const dir = directionRef(e.directionId);
    const stus = e.stopTimeUpdates;
    for (let i = 0; i < stus.length; i++) {
      const stu = stus[i];
      const time = stu.arrivalTime ?? stu.departureTime;
      if (time === undefined) continue;
      const onward: { stopId: string; time: number }[] = [];
      const jEnd = Math.min(stus.length, i + 1 + MAX_ONWARD_STOPS);
      for (let j = i + 1; j < jEnd; j++) {
        const t = stus[j].arrivalTime ?? stus[j].departureTime;
        if (t !== undefined) onward.push({ stopId: stus[j].stopId, time: t });
      }
      const byAgency = (index[agency] ??= {});
      const visits = (byAgency[stu.stopId] ??= []);
      visits.push({ lineRef: line, directionRef: dir, vehicleRef: e.vehicleId, expectedArrival: time, onward });
    }
  }
  for (const agency of Object.keys(index))
    for (const stopId of Object.keys(index[agency]))
      index[agency][stopId].sort((a, b) => a.expectedArrival - b.expectedArrival);
  return index;
}
