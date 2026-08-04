import { describe, it, expect } from "vitest";
import { decodeTripUpdates } from "../../src/gtfsrt/decode";

// A verbatim slice of a real 511.org Regional Gateway GTFS-RT trip-updates feed
// (`GET /transit/tripupdates?agency=RG`), captured 2026-07-10. It is the FeedHeader
// plus the first four FeedEntity records copied byte-for-byte off the wire, base64'd
// so the Workers test pool needs no filesystem access.
//
// This guards the exact bug that shipped in #76: the decoder had the StopTimeUpdate
// field numbers wrong (treated field 2 as stop_id and field 4 as departure), which
// self-consistent synthetic fixtures could never catch — the misaligned reader walked
// off a real stop_id string and threw "unsupported wire type N". Real bytes are the
// only fixture that exercises the true GTFS-RT layout: arrival=2, departure=3, stop_id=4.
const FIXTURE_B64 = [
  "Cg0KAzEuMBAAGP3PxtIGEvEDCggxMDAyNTAyMBrkAwosCgtBQzoxMDAyNTAyMBIIMjA6MDA6MDAaCDIwMjYwNzEwIAAqBUFDOjcz",
  "MAASEwgBGgYQsOPG0gYiBTU1NTk5KAASEwgCEgYQieTG0gYiBTU2MjY2KAASEwgDEgYQl+TG0gYiBTU1NTI3KAASEwgEEgYQ0eTG",
  "0gYiBTU1MzU2KAASEwgFEgYQ7eTG0gYiBTUwNTU0KAASEwgGEgYQ/OTG0gYiBTUwOTk1KAASEwgHEgYQmeXG0gYiBTUwOTA5KAAS",
  "EwgIEgYQt+XG0gYiBTU4ODgyKAASEwgJEgYQ2ubG0gYiBTU5MzExKAASEwgKEgYQ5ubG0gYiBTU0NDIxKAASEwgLEgYQpufG0gYi",
  "BTUzNTk3KAASEwgMEgYQo+jG0gYiBTU1NTUyKAASEwgNEgYQ6+jG0gYiBTU5MzM2KAASEwgOEgYQ9ujG0gYiBTUxNDQzKAASEwgP",
  "EgYQh+nG0gYiBTUzODk5KAASEwgQEgYQ8OnG0gYiBTU4NTU2KAASEwgREgYQlOrG0gYiBTU4ODMyKAASEwgSEgYQt+rG0gYiBTU1",
  "NDI4KAASEwgTEgYQw+rG0gYiBTUwMTE3KAASEwgUEgYQ3evG0gYiBTUwMjc1KAAaCgoEMTY3MRIAGgAg7c/G0gYS7gIKCDEwMDM5",
  "MDIwGuECCiwKC0FDOjEwMDM5MDIwEggyMDowMTowMBoIMjAyNjA3MTAgACoFQUM6MjIwARITCAEaBhCv5cbSBiIFNTY1NTcoABIT",
  "CAISBhDn5cbSBiIFNTEwNjMoABITCAMSBhDV5sbSBiIFNTQ5MDAoABITCAQSBhCV58bSBiIFNTk0ODgoABITCAUSBhCz58bSBiIF",
  "NTU3NTgoABITCAYSBhDh58bSBiIFNTEzNTMoABITCAcSBhD758bSBiIFNTEyMjcoABIbCAgSBhC/6MbSBhoGEL/oxtIGIgU1NTU2",
  "NCgAEhMICRIGEIvpxtIGIgU1NTU3MCgAEhMIChIGEOnpxtIGIgU1ODg1OCgAEhsICxIGELHqxtIGGgYQ8OrG0gYiBTU1NTU3KAAS",
  "EwgMEgYQruvG0gYiBTUxNTI4KAASEwgNEgYQzOvG0gYiBTUzMzI5KAAaCgoEMTU3NxIAGgAg7c/G0gYS3wIKCDEwMDQwMDIwGtIC",
  "Ci0KC0FDOjEwMDQwMDIwEggxODo0NTowMBoIMjAyNjA3MTAgACoGQUM6NzJMMAESEwgOEgYQy9DG0gYiBTU1MTAwKAASEwgPEgYQ",
  "8NHG0gYiBTUzMDIxKAASEwgQEgYQ1tLG0gYiBTU1NTYyKAASEwgREgYQqdTG0gYiBTU4ODU1KAASEwgSEgYQpNXG0gYiBTU1MTE3",
  "KAASEwgTEgYQ+9XG0gYiBTUyOTQ5KAASEwgUEgYQgNjG0gYiBTU1NTMwKAASEwgVEgYQ09nG0gYiBTU4MzAwKAASEwgWEgYQxtrG",
  "0gYiBTU1Mjk5KAASEwgXEgYQitvG0gYiBTU1ODExKAASEwgYEgYQ49vG0gYiBTUxNzU3KAASEwgZEgYQ/9zG0gYiBTU2NzU3KAAS",
  "EwgaEgYQ0t3G0gYiBTU1ODg4KAAaCgoEMTUzMBIAGgAg7c/G0gYSiwEKCDEwMDQ0MDIwGn8KLAoLQUM6MTAwNDQwMjASCDE4OjA0",
  "OjAwGggyMDI2MDcxMCAAKgVBQzo1NzABEhMIRBIGEPrPxtIGIgU1NDQxMCgAEhMIRRIGEK7QxtIGIgU1MDQ4NygAEhMIRhIGEIjR",
  "xtIGIgU1MTQxNigAGgoKBDIyNDASABoAIO3PxtIG",
].join("");

function fixtureBytes(): Uint8Array {
  const bin = atob(FIXTURE_B64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

describe("decodeTripUpdates against a real 511 RG feed slice", () => {
  const out = decodeTripUpdates(fixtureBytes());

  it("decodes every entity without a wire-type error", () => {
    expect(out).toHaveLength(4);
  });

  it("reads the correct trip, route and direction", () => {
    expect(out[0].tripId).toBe("AC:10025020");
    expect(out[0].routeId).toBe("AC:73");
    expect(out[0].directionId).toBe(0);
  });

  it("maps stop_id (field 4) and arrival/departure (fields 2/3) correctly", () => {
    // First stop of the trip: departure only, no arrival.
    expect(out[0].stopTimeUpdates[0]).toEqual({
      stopSequence: 1,
      stopId: "55599",
      departureTime: 1783738800,
    });
    // A downstream stop: arrival, no departure.
    expect(out[0].stopTimeUpdates[1]).toEqual({
      stopSequence: 2,
      stopId: "56266",
      arrivalTime: 1783738889,
    });
  });
});
