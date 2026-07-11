import { Reader } from "./protobuf";

export interface StopTimeUpdate {
  stopSequence: number;
  stopId: string;
  arrivalTime?: number;
  departureTime?: number;
}
export interface TripUpdateEntity {
  tripId: string;
  routeId: string;
  directionId?: number;
  vehicleId?: string;
  stopTimeUpdates: StopTimeUpdate[];
}

function readStopTimeEvent(buf: Uint8Array): number | undefined {
  const r = new Reader(buf);
  let time: number | undefined;
  while (!r.eof()) {
    const { field, wire } = r.tag();
    if (field === 2 && wire === 0) time = r.varint(); // time (ignore delay=field 1)
    else r.skip(wire);
  }
  return time;
}

function readStopTimeUpdate(buf: Uint8Array): StopTimeUpdate {
  const r = new Reader(buf);
  const out: StopTimeUpdate = { stopSequence: 0, stopId: "" };
  while (!r.eof()) {
    const { field, wire } = r.tag();
    // GTFS-RT StopTimeUpdate: stop_sequence=1, arrival=2, departure=3, stop_id=4.
    if (field === 1 && wire === 0) out.stopSequence = r.varint();
    else if (field === 2 && wire === 2) out.arrivalTime = readStopTimeEvent(r.bytes());
    else if (field === 3 && wire === 2) out.departureTime = readStopTimeEvent(r.bytes());
    else if (field === 4 && wire === 2) out.stopId = r.string();
    else r.skip(wire);
  }
  return out;
}

function readTrip(buf: Uint8Array): Pick<TripUpdateEntity, "tripId" | "routeId" | "directionId"> {
  const r = new Reader(buf);
  const out = { tripId: "", routeId: "", directionId: undefined as number | undefined };
  while (!r.eof()) {
    const { field, wire } = r.tag();
    if (field === 1 && wire === 2) out.tripId = r.string();
    else if (field === 5 && wire === 2) out.routeId = r.string();
    else if (field === 6 && wire === 0) out.directionId = r.varint();
    else r.skip(wire);
  }
  return out;
}

function readVehicleId(buf: Uint8Array): string | undefined {
  const r = new Reader(buf);
  let id: string | undefined;
  while (!r.eof()) {
    const { field, wire } = r.tag();
    if (field === 1 && wire === 2) id = r.string();
    else r.skip(wire);
  }
  return id;
}

function readTripUpdate(buf: Uint8Array): TripUpdateEntity {
  const r = new Reader(buf);
  const out: TripUpdateEntity = { tripId: "", routeId: "", stopTimeUpdates: [] };
  while (!r.eof()) {
    const { field, wire } = r.tag();
    if (field === 1 && wire === 2) Object.assign(out, readTrip(r.bytes()));
    else if (field === 2 && wire === 2) out.stopTimeUpdates.push(readStopTimeUpdate(r.bytes()));
    else if (field === 3 && wire === 2) out.vehicleId = readVehicleId(r.bytes());
    else r.skip(wire);
  }
  return out;
}

export function decodeTripUpdates(buf: Uint8Array): TripUpdateEntity[] {
  const r = new Reader(buf);
  const out: TripUpdateEntity[] = [];
  while (!r.eof()) {
    const { field, wire } = r.tag();
    if (field === 2 && wire === 2) {
      // FeedEntity — find its trip_update (field 3)
      const ent = new Reader(r.bytes());
      while (!ent.eof()) {
        const t = ent.tag();
        if (t.field === 3 && t.wire === 2) out.push(readTripUpdate(ent.bytes()));
        else ent.skip(t.wire);
      }
    } else r.skip(wire);
  }
  return out;
}
