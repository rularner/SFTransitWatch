import { decodeTripUpdates } from "./decode";
import { buildArrivalsIndex, type ArrivalsIndex } from "./indexBuilder";
import { toStopMonitoringJson } from "./siri";
import {
  type Env, canMakeUpstreamRequest, LAST_UPSTREAM_FETCH_KEY,
  tryAcquireRefreshLock, releaseRefreshLock, type CachedStops,
} from "../index";

export const RG_SNAPSHOT_TTL_MS = 90_000;
const SNAPSHOT_KEY = "https://gtfsrt.internal/RG";
const UPSTREAM = "https://api.511.org/transit/tripupdates";

export async function gunzipIfNeeded(res: Response): Promise<Uint8Array> {
  const raw = new Uint8Array(await res.arrayBuffer());
  const gzipped = res.headers.get("Content-Encoding") === "gzip" || (raw[0] === 0x1f && raw[1] === 0x8b);
  if (!gzipped) return raw;
  const ds = new Response(new Blob([raw]).stream().pipeThrough(new DecompressionStream("gzip")));
  return new Uint8Array(await ds.arrayBuffer());
}

async function readSnapshot(): Promise<{ index: ArrivalsIndex; fetchedAt: number } | null> {
  const hit = await caches.default.match(new Request(SNAPSHOT_KEY));
  if (!hit) return null;
  const fetchedAt = Number(hit.headers.get("X-Fetched-At-Ms") ?? "0");
  return { index: (await hit.json()) as ArrivalsIndex, fetchedAt };
}

async function writeSnapshot(index: ArrivalsIndex, fetchedAt: number): Promise<void> {
  await caches.default.put(new Request(SNAPSHOT_KEY), new Response(JSON.stringify(index), {
    headers: { "Content-Type": "application/json", "Cache-Control": `max-age=${RG_SNAPSHOT_TTL_MS / 1000}`, "X-Fetched-At-Ms": String(fetchedAt) },
  }));
}

async function refreshSnapshot(env: Env, now: number): Promise<ArrivalsIndex> {
  const u = new URL(UPSTREAM);
  u.searchParams.set("agency", "RG");
  u.searchParams.set("api_key", env.API_511_KEY);
  const res = await fetch(u.toString());
  const bytes = await gunzipIfNeeded(res);
  const index = buildArrivalsIndex(decodeTripUpdates(bytes));
  await writeSnapshot(index, now);
  await env.TRANSIT_CACHE.put(LAST_UPSTREAM_FETCH_KEY, String(now), { expirationTtl: 6 * 60 * 60 });
  return index;
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

export async function handleStopMonitoring(url: URL, env: Env, ctx: ExecutionContext): Promise<Response> {
  const agency = url.searchParams.get("agency") ?? "SF";
  const stopCode = url.searchParams.get("stopCode") ?? "";
  const maxOnward = Number(url.searchParams.get("MaximumNumberOfCallsOnwards") ?? "10");
  const now = Date.now();

  let snap = await readSnapshot();
  const fresh = snap !== null && now - snap.fetchedAt < RG_SNAPSHOT_TTL_MS;

  if (!fresh) {
    const gotLock = await tryAcquireRefreshLock(env);
    if (gotLock) {
      try {
        if (await canMakeUpstreamRequest(env, now)) {
          snap = { index: await refreshSnapshot(env, now), fetchedAt: now };
        }
      } finally {
        await releaseRefreshLock(env);
      }
    }
    // if lock not acquired or budget not available, fall through with stale (or null) snap
  }

  const visits = snap?.index[agency]?.[stopCode] ?? [];
  const stopName = await loadStopNames(env, agency);
  const json = toStopMonitoringJson({ stopCode, visits, maxOnward, stopName });
  return new Response(JSON.stringify(json), {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
      "X-Cache-Status": fresh ? "HIT" : "MISS",
    },
  });
}
