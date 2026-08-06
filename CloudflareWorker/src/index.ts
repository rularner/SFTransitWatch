import { verifySubscription, checkAppStoreAuth } from "./appstore";
import { handleStopMonitoring } from "./gtfsrt/proxy";
import { verifyAppleTransactionJWS, WORKER_PROXY_PRODUCT_IDS } from "./applejws";

const UPSTREAM_BASE_URL = "https://api.511.org/transit";
const FRESH_TTL_SECONDS = 60;
export const STALE_TTL_SECONDS = 6 * 60 * 60;
const MIN_UPSTREAM_INTERVAL_MS = 60_000;
export const LAST_UPSTREAM_FETCH_KEY = "meta:last_upstream_fetch_ms";
const STOPS_FRESH_TTL_SECONDS = 24 * 60 * 60;
const DEFAULT_STOPS_COUNT = 30;
const MAX_STOPS_COUNT = 100;
const TIMETABLE_FRESH_TTL_SECONDS = 24 * 60 * 60;
const TIMETABLE_STALE_TTL_SECONDS = 7 * 24 * 60 * 60;
const PROVISION_RATE_LIMIT = { maxRequests: 5, windowSeconds: 10 * 60 };
const TOKEN_EXCHANGE_RATE_LIMIT = { maxRequests: 10, windowSeconds: 10 * 60 };
const LOG_RATE_LIMIT = { maxRequests: 60, windowSeconds: 15 * 60 };
export const PROXY_RATE_LIMIT = { maxRequests: 60, windowSeconds: 60 };
const SANDBOX_PROXY_RATE_LIMIT = { maxRequests: 15, windowSeconds: 60 };

function proxyRateLimitFor(tier: "paid" | "sandbox"): { maxRequests: number; windowSeconds: number } {
    return tier === "sandbox" ? SANDBOX_PROXY_RATE_LIMIT : PROXY_RATE_LIMIT;
}
const SUBSCRIPTION_GRACE_SECONDS = 3 * 24 * 60 * 60;
const MAX_TOKENS_PER_SUBSCRIPTION = 5;
const SANDBOX_MIN_TTL_SECONDS = 24 * 60 * 60;
const SANDBOX_MAX_TTL_SECONDS = 7 * 24 * 60 * 60;

type TtlPair = { fresh: number; stale: number };

const DEFAULT_TTL: TtlPair = { fresh: FRESH_TTL_SECONDS, stale: STALE_TTL_SECONDS };
const TIMETABLE_TTL: TtlPair = { fresh: TIMETABLE_FRESH_TTL_SECONDS, stale: TIMETABLE_STALE_TTL_SECONDS };

function ttlForEndpoint(endpoint: string): TtlPair {
    return endpoint === "StopTimetable" || endpoint === "Timetable"
        ? TIMETABLE_TTL
        : DEFAULT_TTL;
}

export interface Env {
	API_511_KEY: string;
	TRANSIT_CACHE: KVNamespace;
	CLIENT_TOKENS: KVNamespace;
	APPSTORE_KEY_ID: string;
	APPSTORE_ISSUER_ID: string;
	APPSTORE_PRIVATE_KEY: string;
	APPSTORE_BUNDLE_ID: string;
	APPSTORE_APP_APPLE_ID: string;
	HEALTHCHECK_TOKEN: string;
	GTFSRT_READER_URL: string;
	GTFSRT_INTERNAL_KEY: string;
}

type CachedResponse = {
	body: string;
	status: number;
	contentType: string;
	fetchedAtMs: number;
};

export type CachedStop = { id: string; name: string; lat: number; lon: number };
export type CachedStops = { stops: CachedStop[]; fetchedAtMs: number };

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		try {
			if (request.method === "OPTIONS") {
				return new Response(null, { status: 204, headers: corsHeaders() });
			}

			const url = new URL(request.url);

			// Registration exchange — unauthenticated, must come before the token gate.
			if (url.pathname === "/worker-token") {
				return await handleWorkerToken(request, env);
			}

			// Self-provision — unauthenticated, must come before the token gate.
			if (url.pathname === "/self-provision") {
				return await handleSelfProvision(request, env);
			}

			// Health check — gated by its own bearer token, must come before the token gate.
			if (url.pathname === "/healthz/appstore") {
				return await handleHealthzAppStore(request, env);
			}

			const auth = await authorizeClient(request, env);
			if (!auth.ok) {
				console.warn(JSON.stringify({ source: "worker-auth", outcome: "rejected", path: url.pathname }));
				return jsonError("Missing or invalid X-App-Token.", 401);
			}
			const keyHashPrefix = (await sha256Hex(env.API_511_KEY)).slice(0, 12);
			console.log(JSON.stringify({
				source: "worker-auth",
				label: auth.client.label,
				method: request.method,
				path: url.pathname,
				keyHashPrefix,
			}));

			// /log has its own token-keyed bucket — must not consume the proxy data budget.
			if (url.pathname === "/log") {
				return await handleLog(request, env, auth.client.tokenHash);
			}

			if (request.method !== "GET") {
				return jsonError("Only GET requests are supported.", 405);
			}

			const endpoint = url.pathname.split("/").filter(Boolean).pop() ?? "";
			if (endpoint === "Stops") {
				// Budget is enforced inside handleStopsRequest so a fresh cache HIT stays
				// free (matching the XML proxy path below) instead of 429ing needlessly.
				return await handleStopsRequest(url, env, auth.client.tokenHash, auth.client.tier);
			}

			if (endpoint === "StopMonitoring") {
				// Bound this endpoint per token — it was previously ungated and could be
				// polled without limit, contending for the shared upstream refresh lock.
				const limit = proxyRateLimitFor(auth.client.tier);
				const allowed = await checkRateLimit(env, "proxy-token", auth.client.tokenHash, limit.maxRequests, limit.windowSeconds);
				if (!allowed) {
					return jsonError("Too many requests.", 429, { "Retry-After": String(limit.windowSeconds) });
				}
				return await handleStopMonitoring(url, env);
			}

			const upstream = buildUpstreamUrl(request.url, env.API_511_KEY);
			if (!upstream.ok) {
				return jsonError(upstream.error, 400);
			}

			const now = Date.now();
			const ttl = ttlForEndpoint(endpoint);
			const cached = await readHotCache(upstream.url);

			// Fresh cache HIT: free — does not consume the token budget.
			if (cached && now - cached.fetchedAtMs < ttl.fresh * 1000) {
				return xmlResponse(cached, "HIT", ttl);
			}

			// Work is required — now gate on the per-token budget.
			const limit = proxyRateLimitFor(auth.client.tier);
			const allowed = await checkRateLimit(env, "proxy-token", auth.client.tokenHash, limit.maxRequests, limit.windowSeconds);
			if (!allowed) {
				if (cached) {
					return xmlResponse(cached, "STALE", ttl);
				}
				console.warn(JSON.stringify({ source: "proxy-rate-limit", outcome: "rate_limited", label: auth.client.label }));
				return jsonError("Too many requests.", 429, { "Retry-After": String(limit.windowSeconds) });
			}

			const canRefreshNow = await canMakeUpstreamRequest(env, now);
			if (!canRefreshNow && cached) {
				// Within the upstream min-interval: serve stale. A background revalidation
				// here could not run anyway (it would re-check the same interval and no-op).
				// A later request outside the window refreshes synchronously via the MISS
				// path below.
				return xmlResponse(cached, "STALE", ttl);
			}
			if (!canRefreshNow && !cached) {
				return jsonError("Rate limited by upstream policy. Retry in a few seconds.", 429, { "Retry-After": "60" });
			}

			const refreshed = await fetchAndCacheUpstream(env, upstream.url, now, ttl);
			if (refreshed.ok) {
				return xmlResponse(refreshed.value, "MISS", ttl);
			}
			if (cached) {
				return xmlResponse(cached, "STALE-UPSTREAM-ERROR", ttl);
			}
			return jsonError(refreshed.error, 502);
		} catch (error) {
			console.error("Unhandled worker error:", error);
			return jsonError("Unexpected worker error.", 500);
		}
	},
} satisfies ExportedHandler<Env>;

function corsHeaders(): HeadersInit {
	return {
		"Access-Control-Allow-Origin": "*",
		"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
		"Access-Control-Allow-Headers": "Content-Type, X-App-Token",
	};
}

function jsonError(message: string, status: number, extraHeaders: HeadersInit = {}): Response {
	return new Response(JSON.stringify({ error: message }), {
		status,
		headers: {
			...corsHeaders(),
			...extraHeaders,
			"Content-Type": "application/json; charset=utf-8",
			"Cache-Control": "no-store",
		},
	});
}

function xmlResponse(cached: CachedResponse, cacheStatus: string, ttl: TtlPair): Response {
	return new Response(cached.body, {
		status: cached.status,
		headers: {
			...corsHeaders(),
			"Content-Type": cached.contentType,
			"Cache-Control": `public, max-age=${ttl.fresh}, stale-if-error=${ttl.stale}`,
			"X-Cache-Status": cacheStatus,
			"X-Cached-At": new Date(cached.fetchedAtMs).toISOString(),
		},
	});
}

const UPSTREAM_PATHS: Record<string, string> = {
	StopMonitoring: "StopMonitoring",
	StopTimetable: "stoptimetable",
	Timetable: "timetable",
};

function buildUpstreamUrl(
	requestUrl: string,
	apiKey: string,
): { ok: true; url: URL } | { ok: false; error: string } {
	const incoming = new URL(requestUrl);
	const segments = incoming.pathname.split("/").filter(Boolean);
	const endpoint = segments[segments.length - 1];

	if (!endpoint || !Object.keys(UPSTREAM_PATHS).includes(endpoint)) {
		return { ok: false, error: "Path must end with /StopMonitoring, /Stops, /StopTimetable, or /Timetable." };
	}

	const upstream = new URL(`${UPSTREAM_BASE_URL}/${UPSTREAM_PATHS[endpoint]}`);
	for (const [key, value] of incoming.searchParams.entries()) {
		if (key !== "api_key") {
			upstream.searchParams.set(key, value);
		}
	}
	upstream.searchParams.set("api_key", apiKey);
	upstream.searchParams.set("format", "json");
	return { ok: true, url: upstream };
}

async function readHotCache(upstreamUrl: URL): Promise<CachedResponse | null> {
	const res = await caches.default.match(new Request(upstreamUrl.toString()));
	if (!res) return null;
	const fetchedAtMs = Number.parseInt(res.headers.get("X-Cached-At-Ms") ?? "", 10);
	if (!Number.isFinite(fetchedAtMs)) return null;
	const body = await res.text();
	const status = Number.parseInt(res.headers.get("X-Origin-Status") ?? "200", 10);
	const contentType = res.headers.get("X-Origin-Content-Type") ?? "application/xml; charset=utf-8";
	return { body, status, contentType, fetchedAtMs };
}

async function writeHotCache(upstreamUrl: URL, cached: CachedResponse, ttl: TtlPair): Promise<void> {
	const res = new Response(cached.body, {
		headers: {
			"Content-Type": cached.contentType,
			"Cache-Control": `max-age=${ttl.stale}`,
			"X-Cached-At-Ms": String(cached.fetchedAtMs),
			"X-Origin-Status": String(cached.status),
			"X-Origin-Content-Type": cached.contentType,
		},
	});
	await caches.default.put(new Request(upstreamUrl.toString()), res);
}

export async function canMakeUpstreamRequest(env: Env, nowMs: number): Promise<boolean> {
	const raw = await env.TRANSIT_CACHE.get(LAST_UPSTREAM_FETCH_KEY);
	const lastMs = raw ? Number.parseInt(raw, 10) : 0;
	if (!Number.isFinite(lastMs)) {
		return true;
	}
	return nowMs - lastMs >= MIN_UPSTREAM_INTERVAL_MS;
}

async function fetchAndCacheUpstream(
	env: Env,
	upstreamUrl: URL,
	nowMs: number,
	ttl: TtlPair,
): Promise<{ ok: true; value: CachedResponse } | { ok: false; error: string }> {
	let response: Response;
	try {
		response = await fetch(upstreamUrl, {
			method: "GET",
			headers: { Accept: "application/json,application/xml;q=0.9,*/*;q=0.1" },
		});
	} catch (error) {
		console.error("Upstream fetch failed:", error);
		return { ok: false, error: "Failed to contact 511 upstream." };
	}

	const contentType = response.headers.get("content-type") ?? "application/xml; charset=utf-8";
	const body = await response.text();
	const cached: CachedResponse = { body, status: response.status, contentType, fetchedAtMs: nowMs };

	if (response.ok) {
		await writeHotCache(upstreamUrl, cached, ttl);
		await env.TRANSIT_CACHE.put(LAST_UPSTREAM_FETCH_KEY, String(nowMs), {
			expirationTtl: STALE_TTL_SECONDS,
		});
		return { ok: true, value: cached };
	}

	// Persist throttling metadata even for upstream errors to avoid a retry storm.
	await env.TRANSIT_CACHE.put(LAST_UPSTREAM_FETCH_KEY, String(nowMs), {
		expirationTtl: STALE_TTL_SECONDS,
	});
	const safeUrl = new URL(upstreamUrl);
	safeUrl.searchParams.delete("api_key");
	const keyHashPrefix = (await sha256Hex(env.API_511_KEY)).slice(0, 12);
	console.error(`Upstream error: HTTP ${response.status} for ${safeUrl} — key_hash_prefix: ${keyHashPrefix} — body: ${body.slice(0, 300)}`);
	return { ok: false, error: `Upstream responded with HTTP ${response.status}.` };
}

const REG_CODE_PREFIX = "reg:";

async function handleWorkerToken(request: Request, env: Env): Promise<Response> {
	if (request.method !== "GET") {
		return jsonError("Only GET requests are supported.", 405);
	}
	const clientIp = request.headers.get("CF-Connecting-IP") ?? "unknown";
	const allowed = await checkRateLimit(env, "token", clientIp, TOKEN_EXCHANGE_RATE_LIMIT.maxRequests, TOKEN_EXCHANGE_RATE_LIMIT.windowSeconds);
	if (!allowed) {
		console.warn(JSON.stringify({ source: "worker-token", outcome: "rate_limited" }));
		return jsonError("Too many requests.", 429, { "Retry-After": String(TOKEN_EXCHANGE_RATE_LIMIT.windowSeconds) });
	}
	const code = new URL(request.url).searchParams.get("code");
	if (!code) {
		return jsonError("Missing code parameter.", 400);
	}
	const kvKey = `${REG_CODE_PREFIX}${code}`;
	const token = await env.CLIENT_TOKENS.get(kvKey);
	if (!token) {
		console.warn(JSON.stringify({ source: "worker-token", outcome: "rejected", reason: "invalid_code" }));
		return jsonError("Invalid or expired registration code.", 401);
	}
	await env.CLIENT_TOKENS.delete(kvKey);
	return new Response(JSON.stringify({ token }), {
		status: 200,
		headers: { ...corsHeaders(), "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
	});
}

const MAX_LOG_BATCH = 50;

async function handleLog(request: Request, env: Env, tokenHash: string): Promise<Response> {
	if (request.method !== "POST") {
		return jsonError("POST required.", 405);
	}

	const allowed = await checkRateLimit(env, "log", tokenHash, LOG_RATE_LIMIT.maxRequests, LOG_RATE_LIMIT.windowSeconds);
	if (!allowed) {
		console.warn(JSON.stringify({ source: "log", outcome: "rate_limited" }));
		return jsonError("Too many requests.", 429, { "Retry-After": String(LOG_RATE_LIMIT.windowSeconds) });
	}

	let parsed: unknown;
	try {
		parsed = await request.json();
	} catch {
		return jsonError("Body must be valid JSON.", 400);
	}

	if (!parsed || typeof parsed !== "object" || !Array.isArray((parsed as { events?: unknown }).events)) {
		return jsonError('Body must be {"events": [...]}.', 400);
	}

	const events = (parsed as { events: unknown[] }).events;
	if (events.length > MAX_LOG_BATCH) {
		return jsonError(`At most ${MAX_LOG_BATCH} events per batch.`, 400);
	}

	for (const event of events) {
		const { install_id: rawId, ...rest } = event as Record<string, unknown>;
		const entry: Record<string, unknown> = { source: "app-telemetry", ...rest };
		if (typeof rawId === "string") {
			entry.install_id_hash = (await sha256Hex(rawId)).slice(0, 16);
		}
		console.log(JSON.stringify(entry));
	}

	return new Response(null, { status: 204, headers: corsHeaders() });
}

async function handleStopsRequest(url: URL, env: Env, tokenHash: string, tier: "paid" | "sandbox"): Promise<Response> {
	const agency = url.searchParams.get("agency") ?? url.searchParams.get("operator_id");
	if (!agency) {
		return jsonError("agency parameter required.", 400);
	}

	const stopsKey = `stops:${agency}`;
	const now = Date.now();

	const raw = await env.TRANSIT_CACHE.get(stopsKey, "json");
	const cached = isValidCachedStops(raw) ? raw : null;
	const isFresh = cached !== null && now - cached.fetchedAtMs < STOPS_FRESH_TTL_SECONDS * 1000;

	let active: CachedStops;
	if (isFresh) {
		// Fresh cache HIT: free — does not consume the token budget.
		active = cached;
	} else {
		// Work (an upstream fetch) is required — now gate on the per-token budget. On limit,
		// serve stale cache if we have it rather than failing the client outright.
		const limit = proxyRateLimitFor(tier);
		const allowed = await checkRateLimit(env, "proxy-token", tokenHash, limit.maxRequests, limit.windowSeconds);
		if (!allowed) {
			if (cached) {
				active = cached;
				return stopsJsonResponse(selectClosestStops(url, active), active.fetchedAtMs);
			}
			return jsonError("Too many requests.", 429, { "Retry-After": String(limit.windowSeconds) });
		}
		const result = await fetchAndCacheAllStops(env, agency, now);
		if (result.ok) {
			active = result.value;
		} else if (cached) {
			active = cached;
		} else {
			return jsonError(result.error, 502);
		}
	}

	return stopsJsonResponse(selectClosestStops(url, active), active.fetchedAtMs);
}

function selectClosestStops(url: URL, active: CachedStops): CachedStop[] {
	const lat = parseFloat(url.searchParams.get("lat") ?? url.searchParams.get("latitude") ?? "");
	const lon = parseFloat(url.searchParams.get("lon") ?? url.searchParams.get("longitude") ?? "");
	const rawCount = parseInt(url.searchParams.get("count") ?? "", 10);
	// parseInt yields a finite number or NaN, and `NaN > 0` is false, so a non-positive or
	// unparseable count (e.g. "count=-5", "count=notanumber") intentionally falls back to
	// DEFAULT_STOPS_COUNT rather than being clamped to a minimum of 1 — this is deliberate,
	// tested behavior, not something to "simplify" into a strict clamp.
	const hasExplicitCount = rawCount > 0;
	const count = hasExplicitCount ? Math.min(rawCount, MAX_STOPS_COUNT) : DEFAULT_STOPS_COUNT;

	if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
		// No location to rank by: stop search (fetchAllStops -> searchStops in the apps) relies
		// on getting the full agency stop list back. Only cap this path if the caller explicitly
		// asked for a count — otherwise capping to `count` would silently break client-side search
		// for the ~99% of stops beyond the first `count` in whatever order the cache holds.
		return hasExplicitCount ? active.stops.slice(0, count) : active.stops;
	}

	return active.stops
		.map((s) => ({ s, d: distanceMeters(s.lat, s.lon, lat, lon) }))
		.sort((a, b) => a.d - b.d)
		.slice(0, count)
		.map((x) => x.s);
}

function isValidCachedStops(raw: unknown): raw is CachedStops {
	if (!raw || typeof raw !== "object") return false;
	const r = raw as Record<string, unknown>;
	return Array.isArray(r.stops) && typeof r.fetchedAtMs === "number";
}

async function fetchAndCacheAllStops(
	env: Env,
	agency: string,
	nowMs: number,
): Promise<{ ok: true; value: CachedStops } | { ok: false; error: string }> {
	const upstreamUrl = new URL(`${UPSTREAM_BASE_URL}/Stops`);
	upstreamUrl.searchParams.set("operator_id", agency);
	upstreamUrl.searchParams.set("api_key", env.API_511_KEY);

	let response: Response;
	try {
		response = await fetch(upstreamUrl, { headers: { Accept: "application/json" } });
	} catch (err) {
		console.error(`Stops upstream fetch failed for ${agency}:`, err);
		return { ok: false, error: "Failed to contact 511 upstream." };
	}

	if (!response.ok) {
		const body = await response.text();
		console.error(`Stops upstream error: HTTP ${response.status} for ${agency} — body: ${body.slice(0, 300)}`);
		return { ok: false, error: `Upstream responded with HTTP ${response.status}.` };
	}

	let data: unknown;
	try {
		data = await response.json();
	} catch {
		console.error(JSON.stringify({ source: "stops-fetch", outcome: "error", reason: "json_parse_failed", agency }));
		return { ok: false, error: "Failed to parse stops JSON from upstream." };
	}

	const cached: CachedStops = { stops: parseStopsFromApi(data), fetchedAtMs: nowMs };
	await env.TRANSIT_CACHE.put(`stops:${agency}`, JSON.stringify(cached), {
		expirationTtl: STOPS_FRESH_TTL_SECONDS * 2,
	});
	return { ok: true, value: cached };
}

function stopsJsonResponse(stops: CachedStop[], fetchedAtMs: number): Response {
	const body = JSON.stringify({
		Contents: {
			dataObjects: {
				ScheduledStopPoint: stops.map((s) => ({
					id: s.id,
					Name: s.name,
					Location: { Latitude: String(s.lat), Longitude: String(s.lon) },
				})),
			},
		},
	});
	return new Response(body, {
		status: 200,
		headers: {
			...corsHeaders(),
			"Content-Type": "application/json; charset=utf-8",
			"Cache-Control": `public, max-age=${STOPS_FRESH_TTL_SECONDS}, stale-if-error=${STALE_TTL_SECONDS}`,
			"X-Cache-Status": "HIT",
			"X-Cached-At": new Date(fetchedAtMs).toISOString(),
		},
	});
}

export function parseStopsFromApi(data: unknown): CachedStop[] {
	if (!data || typeof data !== "object") return [];
	const root = data as Record<string, unknown>;
	const contents = root["Contents"] as Record<string, unknown> | undefined;
	if (!contents) return [];
	const dataObjects = contents["dataObjects"] as Record<string, unknown> | undefined;
	if (!dataObjects) return [];
	const points = dataObjects["ScheduledStopPoint"];
	if (!Array.isArray(points)) return [];

	return points.flatMap((pt: unknown) => {
		if (!pt || typeof pt !== "object") return [];
		const p = pt as Record<string, unknown>;
		const id = p["id"];
		const name = p["Name"];
		const loc = p["Location"] as Record<string, unknown> | undefined;
		if (typeof id !== "string" || typeof name !== "string" || !loc) return [];
		const lat = parseFloat(String(loc["Latitude"] ?? ""));
		const lon = parseFloat(String(loc["Longitude"] ?? ""));
		if (!Number.isFinite(lat) || !Number.isFinite(lon)) return [];
		return [{ id, name, lat, lon }];
	});
}

export function distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
	const R = 6_371_000;
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(lat2 - lat1);
	const dLon = toRad(lon2 - lon1);
	const a =
		Math.sin(dLat / 2) ** 2 +
		Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
	return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function checkRateLimit(
	env: Env,
	prefix: string,
	ip: string,
	maxRequests: number,
	windowSeconds: number,
): Promise<boolean> {
	const bucket = String(Math.floor(Date.now() / 1000 / windowSeconds));
	const ipHash = (await sha256Hex(ip)).slice(0, 16);
	const key = `ratelimit:${prefix}:${ipHash}:${bucket}`;
	const raw = await env.TRANSIT_CACHE.get(key);
	const count = raw ? parseInt(raw, 10) : 0;
	if (count >= maxRequests) return false;
	await env.TRANSIT_CACHE.put(key, String(count + 1), { expirationTtl: windowSeconds * 2 });
	return true;
}

async function handleHealthzAppStore(request: Request, env: Env): Promise<Response> {
	if (request.method !== "GET") {
		return jsonError("Only GET requests are supported.", 405);
	}

	const expected = env.HEALTHCHECK_TOKEN;
	const authHeader = request.headers.get("Authorization") ?? "";
	if (!expected || authHeader !== `Bearer ${expected}`) {
		return jsonError("Unauthorized.", 401);
	}

	const checks: Record<string, { ok: boolean; status?: number; error?: string }> = {};

	try {
		if (!env.SELF_PROVISION_PUBLIC_KEY) {
			throw new Error("SELF_PROVISION_PUBLIC_KEY not configured");
		}
		const spkiBytes = Uint8Array.from(atob(env.SELF_PROVISION_PUBLIC_KEY), (c) => c.charCodeAt(0));
		await crypto.subtle.importKey("spki", spkiBytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
		checks.selfProvisionKey = { ok: true };
	} catch (err) {
		console.error("Healthcheck selfProvisionKey check failed", err);
		checks.selfProvisionKey = { ok: false, error: "Self-provision key check failed" };
	}

	try {
		checks.appStoreAuth = await checkAppStoreAuth(env);
	} catch (err) {
		console.error("Healthcheck appStoreAuth check failed", err);
		checks.appStoreAuth = { ok: false, error: "App Store auth check failed" };
	}

	const ok = checks.selfProvisionKey.ok && checks.appStoreAuth.ok;
	return new Response(JSON.stringify({ ok, checks }), {
		status: ok ? 200 : 503,
		headers: {
			...corsHeaders(),
			"Content-Type": "application/json; charset=utf-8",
			"Cache-Control": "no-store",
		},
	});
}

interface SubscriptionTokenIndexEntry {
    hash: string;
    createdAtMs: number;
    expiresAtMs: number;
}

async function recordTokenForSubscription(
    env: Env,
    originalTransactionId: string,
    entry: SubscriptionTokenIndexEntry,
): Promise<void> {
    const indexKey = `subtok:${originalTransactionId}`;
    const now = Date.now();
    const raw = (await env.CLIENT_TOKENS.get(indexKey, "json")) as SubscriptionTokenIndexEntry[] | null;
    const live = (raw ?? []).filter((e) => e.expiresAtMs > now);
    live.push(entry);
    live.sort((a, b) => a.createdAtMs - b.createdAtMs);
    while (live.length > MAX_TOKENS_PER_SUBSCRIPTION) {
        const evicted = live.shift();
        if (evicted) await env.CLIENT_TOKENS.delete(evicted.hash);
    }
    const maxExpiresAtMs = Math.max(...live.map((e) => e.expiresAtMs));
    const ttlSeconds = Math.max(60, Math.ceil((maxExpiresAtMs - now) / 1000));
    await env.CLIENT_TOKENS.put(indexKey, JSON.stringify(live), { expirationTtl: ttlSeconds });
}

function clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
}

function tokenTtlSeconds(tier: "paid" | "sandbox", remainingSeconds: number): number {
    if (tier === "paid") {
        return remainingSeconds + SUBSCRIPTION_GRACE_SECONDS;
    }
    return clamp(remainingSeconds, SANDBOX_MIN_TTL_SECONDS, SANDBOX_MAX_TTL_SECONDS);
}

async function handleSelfProvision(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
        return jsonError("Only POST requests are supported.", 405);
    }

    const clientIp = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const allowed = await checkRateLimit(env, "provision", clientIp, PROVISION_RATE_LIMIT.maxRequests, PROVISION_RATE_LIMIT.windowSeconds);
    if (!allowed) {
        console.warn(JSON.stringify({ source: "self-provision", outcome: "rate_limited" }));
        return jsonError("Too many requests.", 429, { "Retry-After": String(PROVISION_RATE_LIMIT.windowSeconds) });
    }

    let parsed: unknown;
    try {
        parsed = await request.json();
    } catch {
        console.warn(JSON.stringify({ source: "self-provision", outcome: "rejected", reason: "invalid_json" }));
        return jsonError("Body must be valid JSON.", 400);
    }

    if (!parsed || typeof parsed !== "object") {
        console.warn(JSON.stringify({ source: "self-provision", outcome: "rejected", reason: "missing_body" }));
        return jsonError('Body must be {"signedTransactionInfo": "<jws>"}', 400);
    }
    const body = parsed as Record<string, unknown>;

    if ("jwt" in body || "originalTransactionId" in body) {
        console.warn(JSON.stringify({ source: "self-provision", outcome: "rejected", reason: "legacy_client" }));
        return jsonError("This app version is no longer supported. Please update.", 400);
    }
    if (typeof body.signedTransactionInfo !== "string" || body.signedTransactionInfo.length === 0) {
        console.warn(JSON.stringify({ source: "self-provision", outcome: "rejected", reason: "missing_signed_transaction_info" }));
        return jsonError('Body must be {"signedTransactionInfo": "<jws>"}', 400);
    }

    const appAppleId = Number.parseInt(env.APPSTORE_APP_APPLE_ID ?? "", 10);
    if (!Number.isInteger(appAppleId) || appAppleId <= 0) {
        console.error(JSON.stringify({ source: "self-provision", outcome: "error", reason: "app_apple_id_not_configured" }));
        return jsonError("Server misconfiguration.", 500);
    }

    const verified = await verifyAppleTransactionJWS(body.signedTransactionInfo, {
        bundleId: env.APPSTORE_BUNDLE_ID,
        appAppleId,
        productIds: WORKER_PROXY_PRODUCT_IDS,
    });
    if (!verified.ok) {
        console.warn(JSON.stringify({ source: "self-provision", outcome: "rejected", reason: "jws_verification_failed", detail: verified.reason }));
        return jsonError("Could not verify the Apple transaction signature.", 401);
    }

    const subscription = await verifySubscription(env, verified.payload.originalTransactionId, verified.payload.environment);
    if (!subscription.active) {
        console.warn(JSON.stringify({ source: "self-provision", outcome: "rejected", reason: "no_active_subscription" }));
        return jsonError("No active subscription.", 403);
    }

    const tier: "paid" | "sandbox" = subscription.environment === "Sandbox" ? "sandbox" : "paid";
    const remainingSeconds = Math.floor((subscription.expiresAtMs - Date.now()) / 1000);
    const ttlSeconds = Math.max(60, tokenTtlSeconds(tier, remainingSeconds));

    const rawToken = crypto.randomUUID();
    const hash = await sha256Hex(rawToken);
    const platform = typeof body.platform === "string" ? body.platform : "unknown";
    const installId = typeof body.install_id === "string" ? body.install_id : "unknown";
    const appVersion = typeof body.app_version === "string" ? body.app_version : "unknown";
    const label = `self-prov:${platform}:${installId.slice(0, 8)}:${appVersion}`;

    await env.CLIENT_TOKENS.put(
        hash,
        JSON.stringify({
            label,
            tier,
            environment: subscription.environment,
            originalTransactionId: verified.payload.originalTransactionId,
            createdAt: new Date().toISOString(),
            subExpiresAt: new Date(subscription.expiresAtMs).toISOString(),
        }),
        { expirationTtl: ttlSeconds },
    );

    await recordTokenForSubscription(env, verified.payload.originalTransactionId, {
        hash,
        createdAtMs: Date.now(),
        expiresAtMs: Date.now() + ttlSeconds * 1000,
    });

    console.log(JSON.stringify({ source: "self-provision", outcome: "ok", label, tier }));

    return new Response(JSON.stringify({ token: rawToken }), {
        status: 200,
        headers: {
            ...corsHeaders(),
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
        },
    });
}

export async function sha256Hex(input: string): Promise<string> {
	const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
	const bytes = new Uint8Array(buf);
	let out = "";
	for (let i = 0; i < bytes.length; i++) {
		out += bytes[i].toString(16).padStart(2, "0");
	}
	return out;
}

type ClientInfo = { label: string; tokenHash: string; tier: "paid" | "sandbox" };

export async function authorizeClient(
	request: Request,
	env: Env,
): Promise<{ ok: true; client: ClientInfo } | { ok: false }> {
	const token = request.headers.get("X-App-Token");
	if (!token) return { ok: false };
	const hash = await sha256Hex(token);
	const value = await env.CLIENT_TOKENS.get(hash, "json");
	if (!value || typeof (value as { label: string }).label !== "string") {
		return { ok: false };
	}
	// Tokens issued before tiering existed (or via the manual issue-token.sh flow)
	// have no `tier` field — default them to "paid" to preserve existing behavior.
	const stored = value as { label: string; tier?: string };
	const tier: "paid" | "sandbox" = stored.tier === "sandbox" ? "sandbox" : "paid";
	return { ok: true, client: { label: stored.label, tokenHash: hash, tier } };
}
