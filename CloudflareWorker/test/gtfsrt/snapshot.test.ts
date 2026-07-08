import { describe, it, expect, beforeAll, beforeEach, vi } from "vitest";
import { SELF, env } from "cloudflare:test";
import { sha256Hex, LAST_UPSTREAM_FETCH_KEY } from "../../src/index";
import { writeVarint, writeField, writeLenField, writeStringField } from "../../src/gtfsrt/protobuf";

// Reuse the encoder helpers to synthesize an RG feed with one SF:44 trip through stop 16393.
function stopTimeEvent(t: number) { return writeField(2, 0, writeVarint(t)); }
function stu(seq: number, id: string, t: number) {
  return [...writeField(1, 0, writeVarint(seq)), ...writeStringField(2, id), ...writeLenField(3, stopTimeEvent(t))];
}
function feedBytes(nowSec: number): Uint8Array {
  const trip = [...writeStringField(1, "t1"), ...writeStringField(5, "SF:44"), ...writeField(6, 0, writeVarint(1))];
  const tu = [...writeLenField(1, trip), ...writeLenField(2, stu(10, "16393", nowSec + 120)),
              ...writeLenField(2, stu(11, "16301", nowSec + 180)), ...writeLenField(3, writeStringField(1, "8751"))];
  return new Uint8Array(writeLenField(2, writeLenField(3, tu)));
}

const TOKEN = "test-token";
// Mirrors the private constants in src/gtfsrt/snapshot.ts / src/index.ts — not exported, so
// hardcoded here (same pattern as the UPSTREAM cache key in test/worker.test.ts).
const SNAPSHOT_CACHE_KEY = "https://gtfsrt.internal/RG";
const REFRESH_LOCK_KEY = "meta:refresh_lock";

beforeAll(async () => {
  const hash = await sha256Hex(TOKEN);
  await (env as any).CLIENT_TOKENS.put(hash, JSON.stringify({ label: "test", createdAt: "2026-05-03T00:00:00Z" }));
  await (env as any).TRANSIT_CACHE.put("stops:SF", JSON.stringify({
    stops: [{ id: "16301", name: "Silver Ave", lat: 0, lon: 0 }], fetchedAtMs: Date.now(),
  }));
});
beforeEach(async () => {
  vi.restoreAllMocks();
  // The Cache API and KV bindings persist across tests in this harness (not per-test isolated),
  // so each test needs a clean snapshot/throttle/lock state to control its own fetch mock.
  await caches.default.delete(new Request(SNAPSHOT_CACHE_KEY));
  await (env as any).TRANSIT_CACHE.delete(LAST_UPSTREAM_FETCH_KEY);
  await (env as any).TRANSIT_CACHE.delete(REFRESH_LOCK_KEY);
});

describe("/StopMonitoring served from GTFS-RT snapshot", () => {
  it("returns SIRI JSON sliced for the requested stop, no per-stop 511 call", async () => {
    const now = Math.floor(Date.now() / 1000);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(feedBytes(now), { status: 200 }));

    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393&MaximumNumberOfCallsOnwards=10", {
      headers: { "X-App-Token": TOKEN },
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    const mvj = body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit[0].MonitoredVehicleJourney;
    expect(mvj.LineRef).toBe("44");
    expect(mvj.DirectionRef).toBe("IB");
    expect(mvj.OnwardCalls.OnwardCall[0].StopPointName).toBe("Silver Ave");
    // The upstream fetch that happened was the RG feed, not a per-stop StopMonitoring proxy.
    expect((globalThis.fetch as any).mock.calls[0][0].toString()).toContain("tripupdates");
    expect((globalThis.fetch as any).mock.calls[0][0].toString()).toContain("agency=RG");
  });

  it("returns an empty visit list (200) for an unknown stop, never 429", async () => {
    const now = Math.floor(Date.now() / 1000);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(feedBytes(now), { status: 200 }));
    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=99999", {
      headers: { "X-App-Token": TOKEN },
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit).toEqual([]);
  });

  it("degrades to 200 with empty visits (never 500) when the upstream 511 call fails, and still records the throttle timestamp", async () => {
    const before = Date.now();
    // Non-OK response with a non-protobuf body. These particular bytes (field=1, wire=3) also
    // crash the hand-rolled wire-format Reader with "unsupported wire type 3" if ever handed to
    // decodeTripUpdates — i.e. this reproduces the pre-fix 500 (decode invoked unconditionally),
    // not just a "response happens to decode to nothing" case.
    const malformedBody = new Uint8Array([0x0b]);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(malformedBody, { status: 500 }));

    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", {
      headers: { "X-App-Token": TOKEN },
    });

    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit).toEqual([]);

    const raw = await (env as any).TRANSIT_CACHE.get(LAST_UPSTREAM_FETCH_KEY);
    expect(raw).not.toBeNull();
    expect(Number(raw)).toBeGreaterThanOrEqual(before);
  });

  it("decodes a gzip-compressed upstream response", async () => {
    const now = Math.floor(Date.now() / 1000);
    const plain = feedBytes(now);
    const compressedStream = new Response(plain).body!.pipeThrough(new CompressionStream("gzip"));
    const compressed = new Uint8Array(await new Response(compressedStream).arrayBuffer());
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(compressed, { status: 200 }));

    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", {
      headers: { "X-App-Token": TOKEN },
    });

    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    const mvj = body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit[0].MonitoredVehicleJourney;
    expect(mvj.LineRef).toBe("44");
  });
});
