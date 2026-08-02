import { type Env, type CachedStops } from "../index";

const PROXY_CACHE_FRESH_MS = 60_000;
const PROXY_CACHE_RETENTION_SECONDS = 6 * 60 * 60;
const PROXY_TIMEOUT_MS = 3_000;

function cacheKeyFor(url: URL): Request {
  return new Request(`https://gtfsrt-proxy.internal${url.pathname}${url.search}`);
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

function clientResponse(body: string, cacheStatus: "HIT" | "MISS" | "STALE"): Response {
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

export async function loadStopNames(env: Env, agency: string): Promise<(stopId: string) => string> {
  const raw = await env.TRANSIT_CACHE.get(`stops:${agency}`);
  const map = new Map<string, string>();
  if (raw) {
    const cached = JSON.parse(raw) as CachedStops;
    for (const s of cached.stops) map.set(s.id, s.name);
  }
  return (stopId: string) => map.get(stopId) ?? stopId;
}

function resolveOnwardNames(body: string, stopName: (stopId: string) => string): string {
  const json = JSON.parse(body) as any;
  for (const visit of json?.ServiceDelivery?.StopMonitoringDelivery?.MonitoredStopVisit ?? []) {
    for (const oc of visit?.MonitoredVehicleJourney?.OnwardCalls?.OnwardCall ?? []) {
      oc.StopPointName = stopName(oc.StopPointRef);
    }
  }
  return JSON.stringify(json);
}

// Thin authenticated proxy: forwards to the reader Lambda's Function URL, resolves onward-call
// stop names from the Worker's own stops:${agency} KV cache (cheap — bounded by maxOnward, not
// the full regional feed), and read-through caches the resolved body per-colo in caches.default.
// Never surfaces a 4xx/5xx to the client for this endpoint — falls back to a stale cache entry,
// then to an empty MonitoredStopVisit[], matching the pre-migration degrade-gracefully contract.
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
    lambdaUrl.search = url.search;
    const res = await fetch(lambdaUrl.toString(), {
      headers: { "X-Internal-Key": env.GTFSRT_INTERNAL_KEY },
      signal: AbortSignal.timeout(PROXY_TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`reader lambda responded HTTP ${res.status}`);

    const stopName = await loadStopNames(env, agency);
    const body = resolveOnwardNames(await res.text(), stopName);
    await writeCachedProxyResponse(cacheKey, body, now);
    return clientResponse(body, "MISS");
  } catch (error) {
    console.error("GTFS-RT reader lambda call failed:", error);
    if (cached) return clientResponse(cached.body, "STALE");
    return clientResponse(emptyStopMonitoringBody(), "MISS");
  }
}
