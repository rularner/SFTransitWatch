const UPSTREAM_BASE_URL = "https://api.511.org/transit";
const FRESH_TTL_SECONDS = 60;
const STALE_TTL_SECONDS = 6 * 60 * 60;
const MIN_UPSTREAM_INTERVAL_MS = 60_000;
const LAST_UPSTREAM_FETCH_KEY = "meta:last_upstream_fetch_ms";
const REFRESH_LOCK_KEY = "meta:refresh_lock";

interface Env {
	API_511_KEY: string;
	APP_TOKEN: string;
	TRANSIT_CACHE: KVNamespace;
}

type CachedResponse = {
	body: string;
	status: number;
	contentType: string;
	fetchedAtMs: number;
};

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		try {
			if (request.method === "OPTIONS") {
				return new Response(null, { status: 204, headers: corsHeaders() });
			}

			const providedToken = request.headers.get("X-App-Token");
			if (!providedToken || providedToken !== env.APP_TOKEN) {
				return jsonError("Missing or invalid X-App-Token.", 401);
			}

			if (request.method !== "GET") {
				return jsonError("Only GET requests are supported.", 405);
			}

			const upstream = buildUpstreamUrl(request.url, env.API_511_KEY);
			if (!upstream.ok) {
				return jsonError(upstream.error, 400);
			}

			const cacheKey = cacheKeyFor(upstream.url);
			const cached = await readCachedResponse(env, cacheKey);
			const now = Date.now();

			if (cached && now - cached.fetchedAtMs < FRESH_TTL_SECONDS * 1000) {
				return xmlResponse(cached, "HIT");
			}

			const canRefreshNow = await canMakeUpstreamRequest(env, now);
			if (!canRefreshNow && cached) {
				const didSchedule = await scheduleBackgroundRefresh(env, ctx, upstream.url, cacheKey, now);
				return xmlResponse(cached, didSchedule ? "STALE-REVALIDATE" : "STALE");
			}

			if (!canRefreshNow && !cached) {
				return jsonError("Rate limited by upstream policy. Retry in a few seconds.", 429, {
					"Retry-After": "60",
				});
			}

			const refreshed = await fetchAndCacheUpstream(env, upstream.url, cacheKey, now);
			if (refreshed.ok) {
				return xmlResponse(refreshed.value, "MISS");
			}

			if (cached) {
				return xmlResponse(cached, "STALE-UPSTREAM-ERROR");
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

function xmlResponse(cached: CachedResponse, cacheStatus: string): Response {
	return new Response(cached.body, {
		status: cached.status,
		headers: {
			...corsHeaders(),
			"Content-Type": cached.contentType,
			"Cache-Control": `public, max-age=${FRESH_TTL_SECONDS}, stale-if-error=${STALE_TTL_SECONDS}`,
			"X-Cache-Status": cacheStatus,
			"X-Cached-At": new Date(cached.fetchedAtMs).toISOString(),
		},
	});
}

function buildUpstreamUrl(
	requestUrl: string,
	apiKey: string,
): { ok: true; url: URL } | { ok: false; error: string } {
	const incoming = new URL(requestUrl);
	const segments = incoming.pathname.split("/").filter(Boolean);
	const endpoint = segments[segments.length - 1];

	if (!endpoint || !["StopMonitoring", "StopPlace"].includes(endpoint)) {
		return { ok: false, error: "Path must end with /StopMonitoring or /StopPlace." };
	}

	const upstream = new URL(`${UPSTREAM_BASE_URL}/${endpoint}`);
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
): Promise<boolean> {
	const gotLock = await tryAcquireRefreshLock(env);
	if (!gotLock) {
		return false;
	}

	ctx.waitUntil(
		(async () => {
			try {
				const allowed = await canMakeUpstreamRequest(env, nowMs);
				if (!allowed) {
					return;
				}
				await fetchAndCacheUpstream(env, upstreamUrl, cacheKey, Date.now());
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
): Promise<{ ok: true; value: CachedResponse } | { ok: false; error: string }> {
	let response: Response;
	try {
		response = await fetch(upstreamUrl, {
			method: "GET",
			headers: {
				Accept: "application/xml,text/xml,*/*",
			},
		});
	} catch (error) {
		console.error("Upstream fetch failed:", error);
		return { ok: false, error: "Failed to contact 511 upstream." };
	}

	const contentType = response.headers.get("content-type") ?? "application/xml; charset=utf-8";
	const body = await response.text();
	const cached: CachedResponse = {
		body,
		status: response.status,
		contentType,
		fetchedAtMs: nowMs,
	};

	if (response.ok) {
		await env.TRANSIT_CACHE.put(cacheKey, JSON.stringify(cached), {
			expirationTtl: STALE_TTL_SECONDS,
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
