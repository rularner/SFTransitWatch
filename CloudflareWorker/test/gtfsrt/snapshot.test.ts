import { describe, it, expect, beforeAll, beforeEach, vi } from "vitest";
import { SELF, env } from "cloudflare:test";
import { sha256Hex, LAST_UPSTREAM_FETCH_KEY, STALE_TTL_SECONDS } from "../../src/index";
import { RG_SNAPSHOT_TTL_MS } from "../../src/gtfsrt/snapshot";
import { writeVarint, writeField, writeLenField, writeStringField } from "../../src/gtfsrt/protobuf";

// Reuse the encoder helpers to synthesize an RG feed with one SF:44 trip through stop 16393.
function stopTimeEvent(t: number) { return writeField(2, 0, writeVarint(t)); }
function stu(seq: number, id: string, t: number) {
  // Real GTFS-RT wire order: stop_sequence(1), arrival(2){time}, stop_id(4).
  return [...writeField(1, 0, writeVarint(seq)), ...writeLenField(2, stopTimeEvent(t)), ...writeStringField(4, id)];
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

  it("degrades to 200 with empty visits (never 500) when the upstream 200 body is corrupt protobuf", async () => {
    const before = Date.now();
    // A 200 OK response (so refreshSnapshot's `!res.ok` guard does NOT trigger) whose body is a
    // single byte that decodes to wire type 7 — unsupported, so decodeTripUpdates -> Reader.skip
    // throws. This only degrades to 200 via the try/catch around refreshSnapshot() in
    // handleStopMonitoring (safety net #2), not via the !res.ok check (safety net #1).
    const corruptBody = new Uint8Array([0x0f]);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(corruptBody, { status: 200 }));

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

describe("snapshot refresh discipline", () => {
  it("does not refetch within the TTL window (second request served from cached snapshot)", async () => {
    const now = Math.floor(Date.now() / 1000);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(feedBytes(now), { status: 200 }));
    const q = "https://example.com/StopMonitoring?agency=SF&stopCode=16393";

    const first = await SELF.fetch(q, { headers: { "X-App-Token": TOKEN } });
    expect(first.status).toBe(200);
    expect(first.headers.get("X-Cache-Status")).toBe("MISS");

    // Within RG_SNAPSHOT_TTL_MS (90s), a second request must be served from the snapshot written
    // by the first request rather than triggering another upstream fetch. Asserting the
    // X-Cache-Status header (rather than the fetch mock's call count) because cross-request
    // Cache-API behavior in this vitest-pool-workers harness is the thing actually under test —
    // a HIT here can only happen if handleStopMonitoring found the snapshot written moments ago
    // still fresh, which is precisely the refresh-discipline behavior this test guards.
    const second = await SELF.fetch(q, { headers: { "X-App-Token": TOKEN } });
    expect(second.status).toBe(200);
    expect(second.headers.get("X-Cache-Status")).toBe("HIT");
  });
});

describe("snapshot stale-serve past the freshness window (spec §8)", () => {
  it("writes the snapshot with a retention window (Cache-Control max-age) that outlives RG_SNAPSHOT_TTL_MS", async () => {
    const now = Math.floor(Date.now() / 1000);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(feedBytes(now), { status: 200 }));

    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", {
      headers: { "X-App-Token": TOKEN },
    });
    expect(res.status).toBe(200);

    const cached = await caches.default.match(new Request(SNAPSHOT_CACHE_KEY));
    expect(cached).toBeDefined();
    // This is the crux of the fix: the Cache API entry must be retained far longer than the 90s
    // freshness window (RG_SNAPSHOT_TTL_MS), or `caches.default.match` starts returning undefined
    // (readSnapshot -> null) right as staleness begins — exactly when the stale-serve path needs
    // the entry to still be there. STALE_TTL_SECONDS (6h) is the same retention the hot-cache path
    // (writeHotCache in ../index.ts) already uses for the same reason.
    expect(cached!.headers.get("Cache-Control")).toBe(`max-age=${STALE_TTL_SECONDS}`);
    expect(STALE_TTL_SECONDS * 1000).toBeGreaterThan(RG_SNAPSHOT_TTL_MS);
  });

  it("serves the last-good snapshot (not empty visits) when it is older than the 90s freshness window and a refresh attempt fails", async () => {
    const now = Math.floor(Date.now() / 1000);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(feedBytes(now), { status: 200 }));
    const q = "https://example.com/StopMonitoring?agency=SF&stopCode=16393";

    // Populate a fresh snapshot.
    const first = await SELF.fetch(q, { headers: { "X-App-Token": TOKEN } });
    expect(first.status).toBe(200);
    expect(first.headers.get("X-Cache-Status")).toBe("MISS");

    // Age the cached snapshot past RG_SNAPSHOT_TTL_MS (90s) by rewriting the same cache entry
    // with an old X-Fetched-At-Ms but the same already-built ArrivalsIndex body — this simulates
    // "90+ seconds have passed" without needing a real clock, and is the only way to control
    // staleness in this harness (the Cache API's own eviction is driven by real wall-clock time,
    // which a fast-running test can't wait out).
    const cachedBefore = await caches.default.match(new Request(SNAPSHOT_CACHE_KEY));
    expect(cachedBefore).toBeDefined();
    const bodyText = await cachedBefore!.text();
    const staleFetchedAt = Date.now() - (RG_SNAPSHOT_TTL_MS + 30_000); // well past the 90s window
    await caches.default.put(new Request(SNAPSHOT_CACHE_KEY), new Response(bodyText, {
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": `max-age=${STALE_TTL_SECONDS}`,
        "X-Fetched-At-Ms": String(staleFetchedAt),
      },
    }));

    // Clear the throttle/lock the first request set, so the second request is allowed to attempt
    // a refresh — and make that attempt fail (simulating a 511 outage). The fix under test is that
    // this failure degrades to the last-good (now-stale) snapshot, not to empty visits.
    await (env as any).TRANSIT_CACHE.delete(LAST_UPSTREAM_FETCH_KEY);
    await (env as any).TRANSIT_CACHE.delete(REFRESH_LOCK_KEY);
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response("", { status: 503 }));

    const second = await SELF.fetch(q, { headers: { "X-App-Token": TOKEN } });
    expect(second.status).toBe(200);
    expect(second.headers.get("X-Cache-Status")).toBe("MISS"); // stale, not fresh — but still served
    const body = (await second.json()) as any;
    const visits = body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit;
    expect(visits.length).toBeGreaterThan(0);
    expect(visits[0].MonitoredVehicleJourney.LineRef).toBe("44");
  });
});
