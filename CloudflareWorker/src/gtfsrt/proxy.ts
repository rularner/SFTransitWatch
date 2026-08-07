import { type Env, type CachedStops } from "../index";

const PROXY_CACHE_FRESH_MS = 60_000;
// Deliberately NOT imported from index.ts's STALE_TTL_SECONDS (same value, 6 * 60 * 60): proxy.ts
// is imported BY index.ts, and importing a value (not just types) back from index.ts here creates
// a real circular runtime dependency that breaks module init order (Cache-Control ends up
// "max-age=undefined" until index.ts finishes evaluating). Kept as its own constant instead.
const PROXY_CACHE_RETENTION_SECONDS = 6 * 60 * 60;
const PROXY_TIMEOUT_MS = 3_000;
const STOP_NAMES_TTL_MS = 5 * 60_000;

// Builds a normalized query string from exactly the params this endpoint understands, in a
// fixed order. Used for BOTH the cache key and the outbound Lambda call so that extra/reordered
// query params from a client can't multiply cache entries (and Lambda invocations) for what is
// logically the same request.
function normalizedQuery(url: URL): string {
  const p = new URLSearchParams();
  p.set("agency", url.searchParams.get("agency") ?? "SF");
  p.set("stopCode", url.searchParams.get("stopCode") ?? "");
  p.set("MaximumNumberOfCallsOnwards", url.searchParams.get("MaximumNumberOfCallsOnwards") ?? "10");
  return p.toString();
}

function cacheKeyFor(url: URL): Request {
  return new Request(`https://gtfsrt-proxy.internal${url.pathname}?${normalizedQuery(url)}`);
}

async function readCachedProxyResponse(cacheKey: Request): Promise<{ body: string; fetchedAtMs: number } | null> {
  const hit = await caches.default.match(cacheKey);
  if (!hit) return null;
  const fetchedAtMs = Number(hit.headers.get("X-Fetched-At-Ms") ?? "0");
  return { body: await hit.text(), fetchedAtMs };
}

async function writeCachedProxyResponse(cacheKey: Request, body: string, fetchedAtMs: number): Promise<void> {
  await caches.default.put(cacheKey, new Response(body, {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": `max-age=${PROXY_CACHE_RETENTION_SECONDS}`,
      "X-Fetched-At-Ms": String(fetchedAtMs),
    },
  }));
}

function clientResponse(body: string, cacheStatus: "HIT" | "MISS" | "STALE" | "ERROR"): Response {
  return new Response(body, {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
      "X-Cache-Status": cacheStatus,
    },
  });
}

function emptyStopMonitoringBody(): string {
  const nowIso = new Date().toISOString();
  return JSON.stringify({
    ServiceDelivery: {
      ResponseTimestamp: nowIso, ProducerRef: "SF", Status: true,
      StopMonitoringDelivery: { version: "1.4", ResponseTimestamp: nowIso, Status: true, MonitoredStopVisit: [] },
    },
  });
}

// Module-scope memoization of the parsed stops:${agency} Map. SF is ~3000 stops; re-fetching
// from KV and re-parsing that blob on every cache-miss request was the dominant CPU cost on
// this path. A flat cache keyed by agency with a fixed TTL is enough here — there are only a
// handful of agencies, no need for LRU eviction.
const stopNamesCache = new Map<string, { map: Map<string, string>; loadedAt: number }>();

export async function loadStopNames(env: Env, agency: string): Promise<(stopId: string) => string> {
  const now = Date.now();
  const memoized = stopNamesCache.get(agency);
  if (memoized && now - memoized.loadedAt < STOP_NAMES_TTL_MS) {
    return (stopId: string) => memoized.map.get(stopId) ?? stopId;
  }

  const raw = await env.TRANSIT_CACHE.get(`stops:${agency}`);
  const map = new Map<string, string>();
  if (raw) {
    const cached = JSON.parse(raw) as CachedStops;
    for (const s of cached.stops) map.set(s.id, s.name);
  }
  stopNamesCache.set(agency, { map, loadedAt: now });
  return (stopId: string) => map.get(stopId) ?? stopId;
}

function hasOnwardCalls(json: any): boolean {
  for (const visit of json?.ServiceDelivery?.StopMonitoringDelivery?.MonitoredStopVisit ?? []) {
    if ((visit?.MonitoredVehicleJourney?.OnwardCalls?.OnwardCall ?? []).length > 0) return true;
  }
  return false;
}

function resolveOnwardNames(json: any, stopName: (stopId: string) => string): void {
  for (const visit of json?.ServiceDelivery?.StopMonitoringDelivery?.MonitoredStopVisit ?? []) {
    for (const oc of visit?.MonitoredVehicleJourney?.OnwardCalls?.OnwardCall ?? []) {
      oc.StopPointName = stopName(oc.StopPointRef);
    }
  }
}

// Thin authenticated proxy: forwards to the reader Lambda's Function URL, resolves onward-call
// stop names from the Worker's own stops:${agency} KV cache (cheap — bounded by maxOnward, not
// the full regional feed), and read-through caches the resolved body per-colo in caches.default.
// Never surfaces a 4xx/5xx to the client for this endpoint — falls back to a stale cache entry,
// then to an empty MonitoredStopVisit[], matching the pre-migration degrade-gracefully contract.
// The empty-fallback case is tagged X-Cache-Status: ERROR (distinct from a genuine MISS) so the
// client can tell "backend is down" apart from "no buses scheduled right now" instead of silently
// rendering both as an empty arrivals list.
export async function handleStopMonitoring(url: URL, env: Env): Promise<Response> {
  const agency = url.searchParams.get("agency") ?? "SF";
  const cacheKey = cacheKeyFor(url);
  const cached = await readCachedProxyResponse(cacheKey);
  const now = Date.now();

  if (cached && now - cached.fetchedAtMs < PROXY_CACHE_FRESH_MS) {
    return clientResponse(cached.body, "HIT");
  }

  try {
    const lambdaUrl = new URL(env.GTFSRT_READER_URL);
    lambdaUrl.search = normalizedQuery(url);
    const res = await fetch(lambdaUrl.toString(), {
      headers: { "X-Internal-Key": env.GTFSRT_INTERNAL_KEY },
      signal: AbortSignal.timeout(PROXY_TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`reader lambda responded HTTP ${res.status}`);

    const rawBody = await res.text();
    const json = JSON.parse(rawBody);
    let body: string;
    if (hasOnwardCalls(json)) {
      const stopName = await loadStopNames(env, agency);
      resolveOnwardNames(json, stopName);
      body = JSON.stringify(json);
    } else {
      // Nothing to resolve — skip the (possibly memoized, possibly not) stops:${agency} KV
      // lookup entirely and cache the Lambda's response verbatim.
      body = rawBody;
    }
    await writeCachedProxyResponse(cacheKey, body, now);
    return clientResponse(body, "MISS");
  } catch (error) {
    console.error("GTFS-RT reader lambda call failed:", error);
    if (cached) return clientResponse(cached.body, "STALE");
    return clientResponse(emptyStopMonitoringBody(), "ERROR");
  }
}
