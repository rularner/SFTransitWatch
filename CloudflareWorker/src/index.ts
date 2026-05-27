const UPSTREAM_BASE_URL = "https://api.511.org/transit";
const FRESH_TTL_SECONDS = 60;
const STALE_TTL_SECONDS = 6 * 60 * 60;
const MIN_UPSTREAM_INTERVAL_MS = 60_000;
const LAST_UPSTREAM_FETCH_KEY = "meta:last_upstream_fetch_ms";
const REFRESH_LOCK_KEY = "meta:refresh_lock";
const STOPS_FRESH_TTL_SECONDS = 24 * 60 * 60;
const TIMETABLE_FRESH_TTL_SECONDS = 24 * 60 * 60;
const TIMETABLE_STALE_TTL_SECONDS = 7 * 24 * 60 * 60;

type TtlPair = { fresh: number; stale: number };

const DEFAULT_TTL: TtlPair = { fresh: FRESH_TTL_SECONDS, stale: STALE_TTL_SECONDS };
const TIMETABLE_TTL: TtlPair = { fresh: TIMETABLE_FRESH_TTL_SECONDS, stale: TIMETABLE_STALE_TTL_SECONDS };

function ttlForEndpoint(endpoint: string): TtlPair {
    return endpoint === "StopTimetable" || endpoint === "Timetable"
        ? TIMETABLE_TTL
        : DEFAULT_TTL;
}

interface Env {
	API_511_KEY: string;
	TRANSIT_CACHE: KVNamespace;
	CLIENT_TOKENS: KVNamespace;
}

type CachedResponse = {
	body: string;
	status: number;
	contentType: string;
	fetchedAtMs: number;
};

export type CachedStop = { id: string; name: string; lat: number; lon: number };
type CachedStops = { stops: CachedStop[]; fetchedAtMs: number };

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

			const auth = await authorizeClient(request, env);
			if (!auth.ok) {
				return jsonError("Missing or invalid X-App-Token.", 401);
			}
			console.log(JSON.stringify({
				source: "worker-auth",
				label: auth.client.label,
				method: request.method,
				path: url.pathname,
			}));
			if (url.pathname === "/log") {
				return await handleLog(request);
			}

			if (request.method !== "GET") {
				return jsonError("Only GET requests are supported.", 405);
			}

			const endpoint = url.pathname.split("/").filter(Boolean).pop() ?? "";
			if (endpoint === "Stops") {
				return await handleStopsRequest(url, env);
			}

			const upstream = buildUpstreamUrl(request.url, env.API_511_KEY);
			if (!upstream.ok) {
				return jsonError(upstream.error, 400);
			}

			const cacheKey = cacheKeyFor(upstream.url);
			const cached = await readCachedResponse(env, cacheKey);
			const now = Date.now();
			const ttl = ttlForEndpoint(endpoint);

			if (cached && now - cached.fetchedAtMs < ttl.fresh * 1000) {
				return xmlResponse(cached, "HIT", ttl);
			}

			const canRefreshNow = await canMakeUpstreamRequest(env, now);
			if (!canRefreshNow && cached) {
				const didSchedule = await scheduleBackgroundRefresh(env, ctx, upstream.url, cacheKey, now, ttl);
				return xmlResponse(cached, didSchedule ? "STALE-REVALIDATE" : "STALE", ttl);
			}

			if (!canRefreshNow && !cached) {
				return jsonError("Rate limited by upstream policy. Retry in a few seconds.", 429, {
					"Retry-After": "60",
				});
			}

			const refreshed = await fetchAndCacheUpstream(env, upstream.url, cacheKey, now, ttl);
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
	StopPlace: "StopPlace",
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
		return { ok: false, error: "Path must end with /StopMonitoring, /StopPlace, /Stops, /StopTimetable, or /Timetable." };
	}

	const upstream = new URL(`${UPSTREAM_BASE_URL}/${UPSTREAM_PATHS[endpoint]}`);
	for (const [key, value] of incoming.searchParams.entries()) {
		if (key !== "api_key") {
			upstream.searchParams.set(key, value);
		}
	}
	upstream.searchParams.set("api_key", apiKey);
	return { ok: true, url: upstream };
}

function cacheKeyFor(upstreamUrl: URL): string {
	return `cache:${upstreamUrl.pathname}?${upstreamUrl.searchParams.toString()}`;
}

async function readCachedResponse(env: Env, cacheKey: string): Promise<CachedResponse | null> {
	const raw = await env.TRANSIT_CACHE.get(cacheKey, "json");
	if (!raw || typeof raw !== "object") {
		return null;
	}
	const candidate = raw as Partial<CachedResponse>;
	if (
		typeof candidate.body !== "string" ||
		typeof candidate.status !== "number" ||
		typeof candidate.contentType !== "string" ||
		typeof candidate.fetchedAtMs !== "number"
	) {
		return null;
	}
	return candidate as CachedResponse;
}

async function canMakeUpstreamRequest(env: Env, nowMs: number): Promise<boolean> {
	const raw = await env.TRANSIT_CACHE.get(LAST_UPSTREAM_FETCH_KEY);
	const lastMs = raw ? Number.parseInt(raw, 10) : 0;
	if (!Number.isFinite(lastMs)) {
		return true;
	}
	return nowMs - lastMs >= MIN_UPSTREAM_INTERVAL_MS;
}

async function scheduleBackgroundRefresh(
	env: Env,
	ctx: ExecutionContext,
	upstreamUrl: URL,
	cacheKey: string,
	nowMs: number,
	ttl: TtlPair,
): Promise<boolean> {
	const gotLock = await tryAcquireRefreshLock(env);
	if (!gotLock) return false;

	ctx.waitUntil(
		(async () => {
			try {
				const allowed = await canMakeUpstreamRequest(env, nowMs);
				if (!allowed) return;
				await fetchAndCacheUpstream(env, upstreamUrl, cacheKey, Date.now(), ttl);
			} finally {
				await releaseRefreshLock(env);
			}
		})(),
	);
	return true;
}

async function fetchAndCacheUpstream(
	env: Env,
	upstreamUrl: URL,
	cacheKey: string,
	nowMs: number,
	ttl: TtlPair,
): Promise<{ ok: true; value: CachedResponse } | { ok: false; error: string }> {
	let response: Response;
	try {
		response = await fetch(upstreamUrl, {
			method: "GET",
			headers: { Accept: "application/xml,text/xml,*/*" },
		});
	} catch (error) {
		console.error("Upstream fetch failed:", error);
		return { ok: false, error: "Failed to contact 511 upstream." };
	}

	const contentType = response.headers.get("content-type") ?? "application/xml; charset=utf-8";
	const body = await response.text();
	const cached: CachedResponse = { body, status: response.status, contentType, fetchedAtMs: nowMs };

	if (response.ok) {
		await env.TRANSIT_CACHE.put(cacheKey, JSON.stringify(cached), {
			expirationTtl: ttl.stale,
		});
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
	console.error(`Upstream error: HTTP ${response.status} for ${safeUrl} — body: ${body.slice(0, 300)}`);
	return { ok: false, error: `Upstream responded with HTTP ${response.status}.` };
}

async function tryAcquireRefreshLock(env: Env): Promise<boolean> {
	const existing = await env.TRANSIT_CACHE.get(REFRESH_LOCK_KEY);
	if (existing) {
		return false;
	}
	await env.TRANSIT_CACHE.put(REFRESH_LOCK_KEY, "1", { expirationTtl: 20 });
	return true;
}

async function releaseRefreshLock(env: Env): Promise<void> {
	await env.TRANSIT_CACHE.delete(REFRESH_LOCK_KEY);
}

const REG_CODE_PREFIX = "reg:";

async function handleWorkerToken(request: Request, env: Env): Promise<Response> {
	if (request.method !== "GET") {
		return jsonError("Only GET requests are supported.", 405);
	}
	const code = new URL(request.url).searchParams.get("code");
	if (!code) {
		return jsonError("Missing code parameter.", 400);
	}
	const kvKey = `${REG_CODE_PREFIX}${code}`;
	const token = await env.CLIENT_TOKENS.get(kvKey);
	if (!token) {
		return jsonError("Invalid or expired registration code.", 401);
	}
	await env.CLIENT_TOKENS.delete(kvKey);
	return new Response(JSON.stringify({ token }), {
		status: 200,
		headers: { ...corsHeaders(), "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
	});
}

const MAX_LOG_BATCH = 50;

async function handleLog(request: Request): Promise<Response> {
	if (request.method !== "POST") {
		return jsonError("POST required.", 405);
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
		console.log(JSON.stringify({ source: "app-telemetry", ...(event as object) }));
	}

	return new Response(null, { status: 204, headers: corsHeaders() });
}

async function handleStopsRequest(url: URL, env: Env): Promise<Response> {
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
		active = cached;
	} else {
		const result = await fetchAndCacheAllStops(env, agency, now);
		if (result.ok) {
			active = result.value;
		} else if (cached) {
			active = cached;
		} else {
			return jsonError(result.error, 502);
		}
	}

	const lat = parseFloat(url.searchParams.get("lat") ?? url.searchParams.get("latitude") ?? "");
	const lon = parseFloat(url.searchParams.get("lon") ?? url.searchParams.get("longitude") ?? "");
	const radius = parseInt(url.searchParams.get("radius") ?? "1000", 10);

	const filtered =
		Number.isFinite(lat) && Number.isFinite(lon)
			? active.stops.filter((s) => distanceMeters(s.lat, s.lon, lat, lon) <= (Number.isFinite(radius) ? radius : 1000))
			: active.stops;

	return stopsJsonResponse(filtered, active.fetchedAtMs);
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
	upstreamUrl.searchParams.set("agency", agency);
	upstreamUrl.searchParams.set("api_key", env.API_511_KEY);

	let response: Response;
	try {
		response = await fetch(upstreamUrl, { headers: { Accept: "application/json" } });
	} catch {
		return { ok: false, error: "Failed to contact 511 upstream." };
	}

	if (!response.ok) {
		return { ok: false, error: `Upstream responded with HTTP ${response.status}.` };
	}

	let data: unknown;
	try {
		data = await response.json();
	} catch {
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

export async function sha256Hex(input: string): Promise<string> {
	const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
	const bytes = new Uint8Array(buf);
	let out = "";
	for (let i = 0; i < bytes.length; i++) {
		out += bytes[i].toString(16).padStart(2, "0");
	}
	return out;
}

type ClientInfo = { label: string };

export async function authorizeClient(
	request: Request,
	env: Env,
): Promise<{ ok: true; client: ClientInfo } | { ok: false }> {
	const token = request.headers.get("X-App-Token");
	if (!token) return { ok: false };
	const hash = await sha256Hex(token);
	const value = await env.CLIENT_TOKENS.get(hash, "json");
	if (!value || typeof (value as ClientInfo).label !== "string") {
		return { ok: false };
	}
	return { ok: true, client: { label: (value as ClientInfo).label } };
}
