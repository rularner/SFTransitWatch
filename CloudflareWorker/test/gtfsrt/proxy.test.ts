import { describe, it, expect, beforeAll, beforeEach, vi } from "vitest";
import { SELF, env } from "cloudflare:test";
import { sha256Hex } from "../../src/index";
import { loadStopNames } from "../../src/gtfsrt/proxy";

const TOKEN = "test-token";

// The normalized cache key proxy.ts now builds for agency=SF&stopCode=16393 with no explicit
// MaximumNumberOfCallsOnwards (defaults to "10"). Kept in sync with normalizedQuery() in
// src/gtfsrt/proxy.ts.
const NORMALIZED_CACHE_KEY = "https://gtfsrt-proxy.internal/StopMonitoring?agency=SF&stopCode=16393&MaximumNumberOfCallsOnwards=10";

function siriBody(onward: { StopPointRef: string; StopPointName: string; ExpectedArrivalTime: string }[] = []): string {
  return JSON.stringify({
    ServiceDelivery: {
      ResponseTimestamp: "2026-08-02T00:00:00Z", ProducerRef: "SF", Status: true,
      StopMonitoringDelivery: {
        version: "1.4", ResponseTimestamp: "2026-08-02T00:00:00Z", Status: true,
        MonitoredStopVisit: [{
          RecordedAtTime: "2026-08-02T00:00:00Z", MonitoringRef: "16393",
          MonitoredVehicleJourney: {
            LineRef: "44", DirectionRef: "IB", OperatorRef: "SF", VehicleRef: "8751",
            MonitoredCall: { StopPointRef: "16393", ExpectedArrivalTime: "2026-08-02T00:05:00Z", AimedArrivalTime: "2026-08-02T00:05:00Z" },
            OnwardCalls: { OnwardCall: onward },
          },
        }],
      },
    },
  });
}

beforeAll(async () => {
  const hash = await sha256Hex(TOKEN);
  await (env as any).CLIENT_TOKENS.put(hash, JSON.stringify({ label: "test", createdAt: "2026-05-03T00:00:00Z" }));
  await (env as any).TRANSIT_CACHE.put("stops:SF", JSON.stringify({
    stops: [{ id: "16301", name: "Silver Ave", lat: 0, lon: 0 }], fetchedAtMs: Date.now(),
  }));
});

beforeEach(async () => {
  vi.restoreAllMocks();
  await caches.default.delete(new Request(NORMALIZED_CACHE_KEY));
});

describe("/StopMonitoring proxy", () => {
  it("forwards to the reader Lambda with the shared secret and resolves onward-call names", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input: any, init: any) => {
      const url = new URL(typeof input === "string" ? input : input.url);
      expect(url.searchParams.get("agency")).toBe("SF");
      expect(url.searchParams.get("stopCode")).toBe("16393");
      expect(init.headers["X-Internal-Key"]).toBeTruthy();
      return new Response(siriBody([{ StopPointRef: "16301", StopPointName: "16301", ExpectedArrivalTime: "2026-08-02T00:06:00Z" }]), { status: 200 });
    });

    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", {
      headers: { "X-App-Token": TOKEN },
    });

    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    const mvj = body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit[0].MonitoredVehicleJourney;
    expect(mvj.LineRef).toBe("44");
    expect(mvj.OnwardCalls.OnwardCall[0].StopPointName).toBe("Silver Ave");
    expect(res.headers.get("X-Cache-Status")).toBe("MISS");
  });

  it("serves a cached response without calling the Lambda again within the freshness window", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(siriBody(), { status: 200 }));
    await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", { headers: { "X-App-Token": TOKEN } });
    fetchMock.mockClear();

    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", { headers: { "X-App-Token": TOKEN } });

    expect(res.headers.get("X-Cache-Status")).toBe("HIT");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("falls back to a stale cached response when the Lambda call fails", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementationOnce(async () => new Response(siriBody(), { status: 200 }));
    await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", { headers: { "X-App-Token": TOKEN } });

    // Backdate the cache entry past the 60s freshness window so the second request actually
    // attempts the Lambda call (and falls through to the STALE path) instead of being served
    // as a fresh HIT — two SELF.fetch calls in a row execute far faster than 60s of real time.
    // Mirrors the seedCache() pattern in test/worker.test.ts.
    const cacheKey = new Request(NORMALIZED_CACHE_KEY);
    const cachedRes = await caches.default.match(cacheKey);
    const cachedBody = await cachedRes!.text();
    await caches.default.put(cacheKey, new Response(cachedBody, {
      headers: { "Content-Type": "application/json", "Cache-Control": "max-age=21600", "X-Fetched-At-Ms": String(Date.now() - 61_000) },
    }));

    vi.spyOn(globalThis, "fetch").mockImplementation(async () => { throw new Error("network error"); });
    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", { headers: { "X-App-Token": TOKEN } });

    expect(res.status).toBe(200);
    expect(res.headers.get("X-Cache-Status")).toBe("STALE");
  });

  it("returns an empty visit list, never an error, when the Lambda fails and there is no cache", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => { throw new Error("network error"); });

    const res = await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", { headers: { "X-App-Token": TOKEN } });

    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit).toEqual([]);
  });

  it("normalizes the query string so reordered/extra params still produce a cache HIT", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(siriBody(), { status: 200 }));
    // First request: canonical param order, no explicit MaximumNumberOfCallsOnwards (defaults to 10).
    await SELF.fetch("https://example.com/StopMonitoring?agency=SF&stopCode=16393", { headers: { "X-App-Token": TOKEN } });
    fetchMock.mockClear();

    // Second request: same three logical params, reordered, plus junk params and an explicit
    // MaximumNumberOfCallsOnwards=10 matching the default the first request got implicitly.
    // Should hit the same normalized cache entry rather than bypassing the cache.
    const res = await SELF.fetch(
      "https://example.com/StopMonitoring?extra=junk&stopCode=16393&MaximumNumberOfCallsOnwards=10&agency=SF&another=noise",
      { headers: { "X-App-Token": TOKEN } },
    );

    expect(res.headers.get("X-Cache-Status")).toBe("HIT");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("memoizes the parsed stops:${agency} Map, skipping a second KV fetch within the TTL window", async () => {
    // Uses a dedicated agency/key so this test can't be affected by other tests' prior calls to
    // loadStopNames("SF") having already warmed the module-scope memoization cache.
    const agency = "TEST-MEMO-AGENCY";
    await (env as any).TRANSIT_CACHE.put(`stops:${agency}`, JSON.stringify({
      stops: [{ id: "1", name: "One", lat: 0, lon: 0 }], fetchedAtMs: Date.now(),
    }));
    const getSpy = vi.spyOn((env as any).TRANSIT_CACHE, "get");

    await loadStopNames(env as any, agency);
    expect(getSpy).toHaveBeenCalledTimes(1);

    await loadStopNames(env as any, agency);
    expect(getSpy).toHaveBeenCalledTimes(1); // still 1 — served from the in-memory memoization
  });
});
