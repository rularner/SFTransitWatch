/// <reference path="../node_modules/@cloudflare/vitest-pool-workers/types/cloudflare-test.d.ts" />
import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from "vitest";
import { SELF, env } from "cloudflare:test";
import { sha256Hex, parseStopsFromApi, distanceMeters, PROXY_RATE_LIMIT } from "../src/index";
import { verifyAppleTransactionJWS, type VerifiedTransaction } from "../src/applejws";

vi.mock("../src/applejws", async (importOriginal) => {
    const actual = await importOriginal<typeof import("../src/applejws")>();
    return { ...actual, verifyAppleTransactionJWS: vi.fn() };
});

const mockVerifyJWS = vi.mocked(verifyAppleTransactionJWS);

const VALID_TOKEN = "test-token";
let VALID_HASH = "";

beforeAll(async () => {
    VALID_HASH = await sha256Hex(VALID_TOKEN);
    await (env as unknown as { CLIENT_TOKENS: KVNamespace }).CLIENT_TOKENS.put(
        VALID_HASH,
        JSON.stringify({ label: "test", createdAt: "2026-05-03T00:00:00Z" }),
    );
});

describe("X-App-Token gate", () => {
    it("rejects requests with no token (401)", async () => {
        const res = await SELF.fetch("https://example.com/StopMonitoring?stopCode=12345");
        expect(res.status).toBe(401);
        const body = (await res.json()) as { error: string };
        expect(body.error).toMatch(/token/i);
    });

    it("rejects requests with the wrong token (401)", async () => {
        const res = await SELF.fetch("https://example.com/StopMonitoring?stopCode=12345", {
            headers: { "X-App-Token": "wrong" },
        });
        expect(res.status).toBe(401);
    });

    it("lets OPTIONS preflight through without a token (204)", async () => {
        const res = await SELF.fetch("https://example.com/StopMonitoring", {
            method: "OPTIONS",
        });
        expect(res.status).toBe(204);
    });

    it("includes X-App-Token in CORS Access-Control-Allow-Headers on preflight", async () => {
        const res = await SELF.fetch("https://example.com/StopMonitoring", {
            method: "OPTIONS",
        });
        expect(res.headers.get("Access-Control-Allow-Headers")).toMatch(/X-App-Token/i);
    });

    it("lets a valid token through (status is whatever the route returns, not 401)", async () => {
        const res = await SELF.fetch("https://example.com/StopMonitoring?stopCode=12345", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        // Real upstream isn't reachable in tests, so this will be 502 or similar —
        // the point is it's NOT 401.
        expect(res.status).not.toBe(401);
    });

    it("rejects requests whose token hashes to a value not in CLIENT_TOKENS (401)", async () => {
        const res = await SELF.fetch("https://example.com/StopMonitoring?stopCode=12345", {
            headers: { "X-App-Token": "not-in-kv" },
        });
        expect(res.status).toBe(401);
    });

    it("logs the device label on a successful authorization", async () => {
        const logs: string[] = [];
        const originalLog = console.log;
        console.log = (msg: unknown) => logs.push(String(msg));
        try {
            await SELF.fetch("https://example.com/StopMonitoring?stopCode=12345", {
                headers: { "X-App-Token": VALID_TOKEN },
            });
        } finally {
            console.log = originalLog;
        }
        expect(logs.some((l) => l.includes('"label":"test"'))).toBe(true);
    });
});

const sampleEvent = () => ({
    ts: "2026-04-25T18:32:11.123Z",
    install_id: "00000000-0000-0000-0000-000000000001",
    platform: "watch",
    app_version: "1.0.0",
    build: "1",
    kind: "fetch_outcome",
    endpoint: "StopMonitoring",
    http_status: 200,
    latency_ms: 412,
    error_kind: null,
    cache_status: "HIT",
});

describe("POST /log", () => {
    it("rejects non-POST methods with 405", async () => {
        const res = await SELF.fetch("https://example.com/log", {
            method: "GET",
            headers: { "X-App-Token": VALID_TOKEN },
        });
        expect(res.status).toBe(405);
    });

    it("rejects malformed JSON with 400", async () => {
        const res = await SELF.fetch("https://example.com/log", {
            method: "POST",
            headers: { "X-App-Token": VALID_TOKEN, "Content-Type": "application/json" },
            body: "not json",
        });
        expect(res.status).toBe(400);
    });

    it("rejects batches over 50 events with 400", async () => {
        const events = Array.from({ length: 51 }, sampleEvent);
        const res = await SELF.fetch("https://example.com/log", {
            method: "POST",
            headers: { "X-App-Token": VALID_TOKEN, "Content-Type": "application/json" },
            body: JSON.stringify({ events }),
        });
        expect(res.status).toBe(400);
    });

    it("accepts a valid batch with 204", async () => {
        const res = await SELF.fetch("https://example.com/log", {
            method: "POST",
            headers: { "X-App-Token": VALID_TOKEN, "Content-Type": "application/json" },
            body: JSON.stringify({ events: [sampleEvent(), sampleEvent()] }),
        });
        expect(res.status).toBe(204);
    });

    it("logs each event with source:app-telemetry prefix", async () => {
        const logs: string[] = [];
        const originalLog = console.log;
        console.log = (msg: string) => logs.push(String(msg));
        try {
            await SELF.fetch("https://example.com/log", {
                method: "POST",
                headers: { "X-App-Token": VALID_TOKEN, "Content-Type": "application/json" },
                body: JSON.stringify({ events: [sampleEvent()] }),
            });
        } finally {
            console.log = originalLog;
        }
        const matched = logs.filter((l) => l.includes('"source":"app-telemetry"'));
        expect(matched.length).toBe(1);
        expect(matched[0]).toContain('"endpoint":"StopMonitoring"');
    });

    it("does not consume the proxy-token data bucket (still 204 when data bucket is full)", async () => {
        const tokenHash = await sha256Hex(VALID_TOKEN);
        const idHash = (await sha256Hex(tokenHash)).slice(0, 16);
        const bucket = String(Math.floor(Date.now() / 1000 / PROXY_RATE_LIMIT.windowSeconds));
        const proxyKey = `ratelimit:proxy-token:${idHash}:${bucket}`;
        try {
            await (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE.put(
                proxyKey, String(PROXY_RATE_LIMIT.maxRequests), { expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2 },
            );

            const res = await SELF.fetch("https://example.com/log", {
                method: "POST",
                headers: { "X-App-Token": VALID_TOKEN, "Content-Type": "application/json" },
                body: JSON.stringify({ events: [] }),
            });
            expect(res.status).toBe(204);
        } finally {
            await (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE.delete(proxyKey);
        }
    });
});

describe("GET /worker-token", () => {
    const TEST_TOKEN = "permanent-token-value";
    const TEST_CODE = "valid-one-time-code";

    beforeAll(async () => {
        await (env as unknown as { CLIENT_TOKENS: KVNamespace }).CLIENT_TOKENS.put(
            `reg:${TEST_CODE}`,
            TEST_TOKEN,
        );
    });

    it("returns 400 when code param is missing", async () => {
        const res = await SELF.fetch("https://example.com/worker-token");
        expect(res.status).toBe(400);
        const body = (await res.json()) as { error: string };
        expect(body.error).toMatch(/code/i);
    });

    it("returns 401 for an unknown code", async () => {
        const res = await SELF.fetch("https://example.com/worker-token?code=no-such-code");
        expect(res.status).toBe(401);
    });

    it("returns the token for a valid code", async () => {
        const res = await SELF.fetch(`https://example.com/worker-token?code=${TEST_CODE}`);
        expect(res.status).toBe(200);
        const body = (await res.json()) as { token: string };
        expect(body.token).toBe(TEST_TOKEN);
    });

    it("deletes the code after first use (one-time)", async () => {
        const code = "single-use-code";
        await (env as unknown as { CLIENT_TOKENS: KVNamespace }).CLIENT_TOKENS.put(
            `reg:${code}`,
            "some-token",
        );
        const first = await SELF.fetch(`https://example.com/worker-token?code=${code}`);
        expect(first.status).toBe(200);
        const second = await SELF.fetch(`https://example.com/worker-token?code=${code}`);
        expect(second.status).toBe(401);
    });

    it("returns 405 for non-GET methods", async () => {
        const res = await SELF.fetch("https://example.com/worker-token?code=x", {
            method: "POST",
        });
        expect(res.status).toBe(405);
    });

    it("is accessible without an X-App-Token header", async () => {
        const code = "no-auth-code";
        await (env as unknown as { CLIENT_TOKENS: KVNamespace }).CLIENT_TOKENS.put(
            `reg:${code}`,
            "no-auth-token",
        );
        const res = await SELF.fetch(`https://example.com/worker-token?code=${code}`);
        expect(res.status).toBe(200);
    });
});

describe("sha256Hex", () => {
    it("hashes the empty string to the known SHA-256 hex digest", async () => {
        const hash = await sha256Hex("");
        expect(hash).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    });

    it("hashes 'test-token' deterministically and returns 64 lowercase hex chars", async () => {
        const a = await sha256Hex("test-token");
        const b = await sha256Hex("test-token");
        expect(a).toBe(b);
        expect(a).toMatch(/^[0-9a-f]{64}$/);
    });

    it("produces different digests for different inputs", async () => {
        const a = await sha256Hex("alpha");
        const b = await sha256Hex("beta");
        expect(a).not.toBe(b);
    });
});

// ---------------------------------------------------------------------------
// Stops cache
// ---------------------------------------------------------------------------

interface StopPoint { id: string; Name: string; Location: { Latitude: string; Longitude: string } }
interface StopsBody { Contents: { dataObjects: { ScheduledStopPoint: StopPoint[] } } }

const STOPS_CACHE = () => (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE;

const SF_STOPS_BLOB = JSON.stringify({
    fetchedAtMs: Date.now(),
    stops: [
        { id: "15725", name: "Market St & 4th St",  lat: 37.7844, lon: -122.4062 },
        { id: "15726", name: "Market St & 5th St",  lat: 37.7845, lon: -122.4073 },
        { id: "16000", name: "Mission & 24th St",   lat: 37.7524, lon: -122.4183 },
    ],
});

describe("distanceMeters", () => {
    it("returns 0 for the same point", () => {
        expect(distanceMeters(37.7844, -122.4062, 37.7844, -122.4062)).toBe(0);
    });

    it("returns a small distance for nearby SF stops (~100 m)", () => {
        const d = distanceMeters(37.7844, -122.4062, 37.7845, -122.4073);
        expect(d).toBeGreaterThan(50);
        expect(d).toBeLessThan(300);
    });

    it("returns a large distance for SF to LA (~560 km)", () => {
        const d = distanceMeters(37.7749, -122.4194, 34.0522, -118.2437);
        expect(d).toBeGreaterThan(500_000);
    });
});

describe("parseStopsFromApi", () => {
    it("parses a well-formed 511.org stops JSON payload", () => {
        const data = {
            Contents: {
                dataObjects: {
                    ScheduledStopPoint: [
                        { id: "15725", Name: "Market & 4th", Location: { Latitude: "37.7844", Longitude: "-122.4062" } },
                    ],
                },
            },
        };
        const stops = parseStopsFromApi(data);
        expect(stops).toHaveLength(1);
        expect(stops[0]).toEqual({ id: "15725", name: "Market & 4th", lat: 37.7844, lon: -122.4062 });
    });

    it("returns empty array for null or missing Contents", () => {
        expect(parseStopsFromApi(null)).toHaveLength(0);
        expect(parseStopsFromApi({})).toHaveLength(0);
        expect(parseStopsFromApi({ Contents: {} })).toHaveLength(0);
    });

    it("skips stops with non-numeric coordinates", () => {
        const data = {
            Contents: {
                dataObjects: {
                    ScheduledStopPoint: [
                        { id: "1", Name: "Good", Location: { Latitude: "37.7", Longitude: "-122.4" } },
                        { id: "2", Name: "Bad",  Location: { Latitude: "n/a",  Longitude: "-122.4" } },
                    ],
                },
            },
        };
        const stops = parseStopsFromApi(data);
        expect(stops).toHaveLength(1);
        expect(stops[0].id).toBe("1");
    });

    it("skips stops missing id or Name", () => {
        const data = {
            Contents: {
                dataObjects: {
                    ScheduledStopPoint: [
                        { Name: "No ID",  Location: { Latitude: "37.7", Longitude: "-122.4" } },
                        { id: "99",       Location: { Latitude: "37.7", Longitude: "-122.4" } },
                    ],
                },
            },
        };
        expect(parseStopsFromApi(data)).toHaveLength(0);
    });
});

describe("GET /Stops (stops cache)", () => {
    beforeAll(async () => {
        await STOPS_CACHE().put("stops:SF", SF_STOPS_BLOB);
    });

    it("returns 400 when agency param is missing", async () => {
        const res = await SELF.fetch("https://example.com/Stops", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        expect(res.status).toBe(400);
    });

    it("returns all stops for the agency when no lat/lon provided", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=SF", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        expect(res.status).toBe(200);
        const body = (await res.json()) as StopsBody;
        expect(body.Contents.dataObjects.ScheduledStopPoint).toHaveLength(3);
    });

    it("orders stops by proximity when lat/lon provided (radius param is ignored)", async () => {
        // radius=1 would have excluded every stop under the old radius-cutoff behavior.
        // Closest-N selection ignores radius entirely and returns everything, nearest first.
        const res = await SELF.fetch(
            "https://example.com/Stops?agency=SF&lat=37.7844&lon=-122.4062&radius=1",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).toBe(200);
        const body = (await res.json()) as StopsBody;
        const ids = body.Contents.dataObjects.ScheduledStopPoint.map((s) => s.id);
        expect(ids).toEqual(["15725", "15726", "16000"]);
    });

    it("returns the closest stops even when far from every stop in the fixture", async () => {
        // Roughly Truckee/Tahoe — ~300km from every SF stop below. Under the old radius
        // cutoff this returned []; closest-N selection always returns the nearest stops.
        const res = await SELF.fetch(
            "https://example.com/Stops?agency=SF&lat=39.3088&lon=-120.9070",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).toBe(200);
        const body = (await res.json()) as StopsBody;
        expect(body.Contents.dataObjects.ScheduledStopPoint).toHaveLength(3);
    });

    it("also accepts latitude/longitude param names", async () => {
        const res = await SELF.fetch(
            "https://example.com/Stops?agency=SF&latitude=37.7844&longitude=-122.4062",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).toBe(200);
        const body = (await res.json()) as StopsBody;
        const ids = body.Contents.dataObjects.ScheduledStopPoint.map((s) => s.id);
        expect(ids[0]).toBe("15725");
    });

    it("returns JSON matching the StopsResponse shape the app parses", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=SF", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        const body = (await res.json()) as StopsBody;
        const first = body.Contents.dataObjects.ScheduledStopPoint[0];
        expect(typeof first.id).toBe("string");
        expect(typeof first.Name).toBe("string");
        expect(typeof first.Location.Latitude).toBe("string");
        expect(typeof first.Location.Longitude).toBe("string");
    });

    it("sets X-Cache-Status: HIT when served from cache", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=SF", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        expect(res.headers.get("X-Cache-Status")).toBe("HIT");
    });

    it("returns 502 when agency has no cached blob and upstream unreachable", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=CT", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        expect(res.status).toBe(502);
    });
});

describe("GET /Stops count param (closest-N selection)", () => {
    // 150 stops on the equator, one step of 0.001° longitude apart (~111 m/step). Distance
    // from (0,0) increases monotonically with index, so "closest N" == "first N by id".
    const COUNT_STOPS_BLOB = JSON.stringify({
        fetchedAtMs: Date.now(),
        stops: Array.from({ length: 150 }, (_, i) => ({
            id: `s${i}`,
            name: `Stop ${i}`,
            lat: 0,
            lon: i * 0.001,
        })),
    });

    beforeAll(async () => {
        await STOPS_CACHE().put("stops:CX", COUNT_STOPS_BLOB);
    });

    it("defaults to the closest 30 stops when count is omitted", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=CX&lat=0&lon=0", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        const body = (await res.json()) as StopsBody;
        const ids = body.Contents.dataObjects.ScheduledStopPoint.map((s) => s.id);
        expect(ids).toHaveLength(30);
        expect(ids[0]).toBe("s0");
        expect(ids[29]).toBe("s29");
    });

    it("honors an explicit count within range", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=CX&lat=0&lon=0&count=10", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        const body = (await res.json()) as StopsBody;
        const ids = body.Contents.dataObjects.ScheduledStopPoint.map((s) => s.id);
        expect(ids).toEqual(Array.from({ length: 10 }, (_, i) => `s${i}`));
    });

    it("clamps count above 100 down to 100", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=CX&lat=0&lon=0&count=500", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        const body = (await res.json()) as StopsBody;
        expect(body.Contents.dataObjects.ScheduledStopPoint).toHaveLength(100);
    });

    it("falls back to the default of 30 for a non-positive or invalid count", async () => {
        const resNegative = await SELF.fetch("https://example.com/Stops?agency=CX&lat=0&lon=0&count=-5", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        const negativeBody = (await resNegative.json()) as StopsBody;
        expect(negativeBody.Contents.dataObjects.ScheduledStopPoint).toHaveLength(30);

        const resInvalid = await SELF.fetch("https://example.com/Stops?agency=CX&lat=0&lon=0&count=notanumber", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        const invalidBody = (await resInvalid.json()) as StopsBody;
        expect(invalidBody.Contents.dataObjects.ScheduledStopPoint).toHaveLength(30);
    });

    it("caps at count when no lat/lon is provided", async () => {
        const res = await SELF.fetch("https://example.com/Stops?agency=CX&count=5", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        const body = (await res.json()) as StopsBody;
        expect(body.Contents.dataObjects.ScheduledStopPoint).toHaveLength(5);
    });

    it("returns the full stop list when no lat/lon and no count are provided", async () => {
        // fetchAllStops(agency:) on both the iOS and watchOS apps calls /Stops with only
        // operator_id — no lat/lon, no count — and feeds the result into client-side stop
        // search. That path must never be silently truncated to DEFAULT_STOPS_COUNT (30);
        // this fixture has 150 stops specifically so a cap-to-30 regression is visible.
        const res = await SELF.fetch("https://example.com/Stops?agency=CX", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        expect(res.status).toBe(200);
        const body = (await res.json()) as StopsBody;
        expect(body.Contents.dataObjects.ScheduledStopPoint).toHaveLength(150);
    });
});

// ---------------------------------------------------------------------------
// Per-token rate limiting on proxy routes
// ---------------------------------------------------------------------------

describe("per-token rate limiting on proxy routes", () => {
    const CACHE = () => (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE;

    // Dedicated token so pre-filling its rate limit doesn't pollute VALID_TOKEN across tests.
    const RL_TOKEN = "rate-limit-test-token-proxy";

    beforeAll(async () => {
        const hash = await sha256Hex(RL_TOKEN);
        await (env as unknown as { CLIENT_TOKENS: KVNamespace }).CLIENT_TOKENS.put(
            hash,
            JSON.stringify({ label: "rl-test", createdAt: "2026-05-01T00:00:00Z" }),
        );
    });

    async function rateLimitKeyForToken(token: string): Promise<string> {
        const tokenHash = await sha256Hex(token);
        const idHash = (await sha256Hex(tokenHash)).slice(0, 16);
        const bucket = String(Math.floor(Date.now() / 1000 / PROXY_RATE_LIMIT.windowSeconds));
        return `ratelimit:proxy-token:${idHash}:${bucket}`;
    }

    beforeEach(async () => {
        const key = await rateLimitKeyForToken(RL_TOKEN);
        await CACHE().delete(key);
    });

    // agency=BA has no seeded stops cache, so serving it needs an upstream fetch — that is
    // the path the per-token budget gates. (A fresh cache HIT is exempt; see the test below.)
    it("returns 429 when the per-token request count has reached the limit", async () => {
        const key = await rateLimitKeyForToken(RL_TOKEN);
        await CACHE().put(key, String(PROXY_RATE_LIMIT.maxRequests), {
            expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2,
        });

        const res = await SELF.fetch("https://example.com/Stops?agency=BA", {
            headers: { "X-App-Token": RL_TOKEN },
        });
        expect(res.status).toBe(429);
    });

    it("includes Retry-After header in the 429 response", async () => {
        const key = await rateLimitKeyForToken(RL_TOKEN);
        await CACHE().put(key, String(PROXY_RATE_LIMIT.maxRequests), {
            expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2,
        });

        const res = await SELF.fetch("https://example.com/Stops?agency=BA", {
            headers: { "X-App-Token": RL_TOKEN },
        });
        expect(res.headers.get("Retry-After")).toBe(String(PROXY_RATE_LIMIT.windowSeconds));
    });

    it("serves a fresh cached /Stops for free even when the token is at the limit", async () => {
        const key = await rateLimitKeyForToken(RL_TOKEN);
        await CACHE().put(key, String(PROXY_RATE_LIMIT.maxRequests), {
            expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2,
        });

        // stops:SF is seeded fresh, so no upstream work is needed and the budget must not apply.
        const res = await SELF.fetch("https://example.com/Stops?agency=SF", {
            headers: { "X-App-Token": RL_TOKEN },
        });
        expect(res.status).toBe(200);
    });

    it("does not rate limit a different token when one token is at the limit", async () => {
        const key = await rateLimitKeyForToken(RL_TOKEN);
        await CACHE().put(key, String(PROXY_RATE_LIMIT.maxRequests), {
            expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2,
        });

        // VALID_TOKEN is clean — use it as the "other" token
        const res = await SELF.fetch("https://example.com/Stops?agency=SF", {
            headers: { "X-App-Token": VALID_TOKEN },
        });
        expect(res.status).not.toBe(429);
        expect(res.status).not.toBe(401);
    });

    it("applies the tighter sandbox limit (15/min) to a sandbox-tier token", async () => {
        const sandboxToken = "sandbox-rate-limit-token";
        const sandboxHash = await sha256Hex(sandboxToken);
        await (env as unknown as { CLIENT_TOKENS: KVNamespace }).CLIENT_TOKENS.put(
            sandboxHash,
            JSON.stringify({ label: "sandbox-test", tier: "sandbox", createdAt: "2026-05-03T00:00:00Z" }),
        );

        for (let i = 0; i < 15; i++) {
            const res = await SELF.fetch("https://example.com/StopMonitoring?stopCode=12345", {
                headers: { "X-App-Token": sandboxToken },
            });
            expect(res.status).not.toBe(429);
        }
        const res = await SELF.fetch("https://example.com/StopMonitoring?stopCode=12345", {
            headers: { "X-App-Token": sandboxToken },
        });
        expect(res.status).toBe(429);
    });
});

describe("timetable endpoint routing", () => {
    it("accepts /StopTimetable and returns non-400, non-401 with valid token", async () => {
        const res = await SELF.fetch(
            "https://example.com/StopTimetable?operatorref=SF&monitoringref=15725",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).not.toBe(400);
        expect(res.status).not.toBe(401);
    });

    it("accepts /Timetable and returns non-400, non-401 with valid token", async () => {
        const res = await SELF.fetch(
            "https://example.com/Timetable?operator_id=SF&line_id=38",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).not.toBe(400);
        expect(res.status).not.toBe(401);
    });

    it("rejects /TripUpdates (not in allowlist) with 400", async () => {
        const res = await SELF.fetch(
            "https://example.com/TripUpdates?agency=SF",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).toBe(400);
    });
});

// ---------------------------------------------------------------------------
// POST /self-provision
// ---------------------------------------------------------------------------


describe("POST /self-provision", () => {
    const TEST_ENV = env as unknown as { CLIENT_TOKENS: KVNamespace; TRANSIT_CACHE: KVNamespace };

    async function clearRateLimitKeys(): Promise<void> {
        const { keys } = await TEST_ENV.TRANSIT_CACHE.list({ prefix: "ratelimit:" });
        await Promise.all(keys.map((k) => TEST_ENV.TRANSIT_CACHE.delete(k.name)));
    }

    beforeEach(async () => {
        mockVerifyJWS.mockReset();
        await clearRateLimitKeys();
    });

    afterEach(() => {
        vi.unstubAllGlobals();
    });

    function b64url(data: ArrayBuffer | string): string {
        const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
        let str = "";
        for (const b of bytes) str += String.fromCharCode(b);
        return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
    }

    function stubVerifiedJWS(overrides: Partial<VerifiedTransaction> = {}): void {
        mockVerifyJWS.mockResolvedValue({
            ok: true,
            payload: {
                originalTransactionId: "1000000000000001",
                transactionId: "2000000000000001",
                bundleId: "org.larner.SFTransitWatch",
                productId: "org.larner.SFTransitWatch.proxy.monthly",
                environment: "Production",
                expiresDateMs: Date.now() + 30 * 24 * 60 * 60 * 1000,
                ...overrides,
            },
        });
    }

    function activeSubscriptionResponse(expiresAtMs = Date.now() + 30 * 24 * 60 * 60 * 1000): Response {
        const jws = `${b64url(JSON.stringify({ alg: "ES256" }))}.${b64url(JSON.stringify({ expiresDate: expiresAtMs }))}.sig`;
        return new Response(
            JSON.stringify({ data: [{ lastTransactions: [{ status: 1, signedTransactionInfo: jws }] }] }),
            { status: 200, headers: { "Content-Type": "application/json" } },
        );
    }

    function expiredSubscriptionResponse(): Response {
        const jws = `${b64url(JSON.stringify({ alg: "ES256" }))}.${b64url(JSON.stringify({ expiresDate: Date.now() - 1000 }))}.sig`;
        return new Response(
            JSON.stringify({ data: [{ lastTransactions: [{ status: 2, signedTransactionInfo: jws }] }] }),
            { status: 200, headers: { "Content-Type": "application/json" } },
        );
    }

    function stubActiveSubscription(expiresAtMs?: number): void {
        vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => activeSubscriptionResponse(expiresAtMs)));
    }

    function postSelfProvision(body: Record<string, unknown>) {
        return SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });
    }

    it("returns 400 when body is missing", async () => {
        const res = await SELF.fetch("https://example.com/self-provision", { method: "POST", headers: { "Content-Type": "application/json" } });
        expect(res.status).toBe(400);
    });

    it("returns 400 when body is not valid JSON", async () => {
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: "not json",
        });
        expect(res.status).toBe(400);
    });

    it("returns 400 when signedTransactionInfo is absent", async () => {
        const res = await postSelfProvision({});
        expect(res.status).toBe(400);
    });

    it("returns 400 when the legacy jwt field is present", async () => {
        const res = await postSelfProvision({ jwt: "x", originalTransactionId: "1" });
        expect(res.status).toBe(400);
    });

    it("returns 400 when the legacy originalTransactionId field is present", async () => {
        const res = await postSelfProvision({ signedTransactionInfo: "x", originalTransactionId: "1" });
        expect(res.status).toBe(400);
    });

    it("returns 401 when JWS verification fails", async () => {
        mockVerifyJWS.mockResolvedValue({ ok: false, reason: "bad signature" });
        const res = await postSelfProvision({ signedTransactionInfo: "x" });
        expect(res.status).toBe(401);
    });

    it("returns 403 when there is no active subscription", async () => {
        stubVerifiedJWS();
        vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => expiredSubscriptionResponse()));
        const res = await postSelfProvision({ signedTransactionInfo: "x" });
        expect(res.status).toBe(403);
    });

    it("returns 503, not 403, when Apple's subscription API fails transiently (not a confirmed lapse)", async () => {
        stubVerifiedJWS();
        vi.stubGlobal("fetch", vi.fn().mockImplementation(async () => new Response(null, { status: 500 })));
        const res = await postSelfProvision({ signedTransactionInfo: "x" });
        expect(res.status).toBe(503);
    });

    it("returns 200 with a token for a valid transaction and active subscription", async () => {
        stubVerifiedJWS();
        stubActiveSubscription();
        const res = await postSelfProvision({ signedTransactionInfo: "x", install_id: "abc", platform: "ios", app_version: "1.0.0" });
        expect(res.status).toBe(200);
        const body = (await res.json()) as { token: string };
        expect(typeof body.token).toBe("string");
        expect(body.token.length).toBeGreaterThan(8);
    });

    it("stores the token with tier 'paid' and environment 'Production' for a Production transaction", async () => {
        stubVerifiedJWS({ environment: "Production" });
        stubActiveSubscription();
        const res = await postSelfProvision({ signedTransactionInfo: "x" });
        const { token } = (await res.json()) as { token: string };
        const hash = await sha256Hex(token);
        const stored = (await TEST_ENV.CLIENT_TOKENS.get(hash, "json")) as { tier: string; environment: string } | null;
        expect(stored?.tier).toBe("paid");
        expect(stored?.environment).toBe("Production");
    });

    it("stores the token with tier 'sandbox' for a Sandbox transaction, TTL clamped to a 24h floor", async () => {
        stubVerifiedJWS({ environment: "Sandbox" });
        // Sandbox subscription expiring in 5 minutes — the floor should still grant 24h.
        stubActiveSubscription(Date.now() + 5 * 60 * 1000);
        const res = await postSelfProvision({ signedTransactionInfo: "x" });
        const { token } = (await res.json()) as { token: string };
        const hash = await sha256Hex(token);
        const stored = (await TEST_ENV.CLIENT_TOKENS.get(hash, "json")) as { tier: string } | null;
        expect(stored?.tier).toBe("sandbox");
        const { keys } = await TEST_ENV.CLIENT_TOKENS.list({ prefix: hash });
        const meta = keys.find((k) => k.name === hash);
        const ttlSeconds = (meta?.expiration ?? 0) - Math.floor(Date.now() / 1000);
        expect(ttlSeconds).toBeGreaterThanOrEqual(24 * 60 * 60 - 5);
        expect(ttlSeconds).toBeLessThanOrEqual(24 * 60 * 60 + 5);
    });

    it("label contains the platform and first 8 chars of install_id from the request body", async () => {
        stubVerifiedJWS();
        stubActiveSubscription();
        const res = await postSelfProvision({
            signedTransactionInfo: "x",
            install_id: "12345678-abcd-ef01-2345-678901234567",
            platform: "watchos",
            app_version: "2.0.0",
        });
        const { token } = (await res.json()) as { token: string };
        const hash = await sha256Hex(token);
        const stored = (await TEST_ENV.CLIENT_TOKENS.get(hash, "json")) as { label: string } | null;
        expect(stored?.label).toBe("self-prov:watchos:12345678:2.0.0");
    });

    it("evicts the oldest token once a subscription has more than 5 live tokens", async () => {
        stubVerifiedJWS({ originalTransactionId: "9999999999999999" });
        stubActiveSubscription();
        const tokens: string[] = [];
        for (let i = 0; i < 6; i++) {
            await clearRateLimitKeys();
            const res = await postSelfProvision({ signedTransactionInfo: "x", install_id: `device-${i}` });
            const { token } = (await res.json()) as { token: string };
            tokens.push(token);
        }
        const firstHash = await sha256Hex(tokens[0]);
        const lastHash = await sha256Hex(tokens[5]);
        expect(await TEST_ENV.CLIENT_TOKENS.get(firstHash)).toBeNull();
        expect(await TEST_ENV.CLIENT_TOKENS.get(lastHash)).not.toBeNull();
    });

    it("is accessible without an X-App-Token header", async () => {
        stubVerifiedJWS();
        stubActiveSubscription();
        const res = await postSelfProvision({ signedTransactionInfo: "x" });
        expect(res.status).not.toBe(401);
    });

    it("returns 405 for non-POST methods", async () => {
        const res = await SELF.fetch("https://example.com/self-provision", { method: "GET" });
        expect(res.status).toBe(405);
    });

    describe("purchase vs refresh rate-limit budgets", () => {
        it("draining the refresh budget (no `purpose`) does not block a purpose:purchase request from the same IP", async () => {
            stubVerifiedJWS();
            stubActiveSubscription();

            for (let i = 0; i < 5; i++) {
                const res = await postSelfProvision({ signedTransactionInfo: "x" });
                expect(res.status).toBe(200);
            }
            const drainedRefresh = await postSelfProvision({ signedTransactionInfo: "x" });
            expect(drainedRefresh.status).toBe(429);

            const purchase = await postSelfProvision({ signedTransactionInfo: "x", purpose: "purchase" });
            expect(purchase.status).toBe(200);
        });

        it("draining the purchase budget does not block a refresh (no `purpose`) request from the same IP", async () => {
            stubVerifiedJWS();
            stubActiveSubscription();

            for (let i = 0; i < 5; i++) {
                const res = await postSelfProvision({ signedTransactionInfo: "x", purpose: "purchase" });
                expect(res.status).toBe(200);
            }
            const drainedPurchase = await postSelfProvision({ signedTransactionInfo: "x", purpose: "purchase" });
            expect(drainedPurchase.status).toBe(429);

            const refresh = await postSelfProvision({ signedTransactionInfo: "x" });
            expect(refresh.status).toBe(200);
        });

        it("treats an unrecognized `purpose` value the same as a missing one (refresh bucket)", async () => {
            stubVerifiedJWS();
            stubActiveSubscription();

            for (let i = 0; i < 5; i++) {
                const res = await postSelfProvision({ signedTransactionInfo: "x", purpose: "bogus" });
                expect(res.status).toBe(200);
            }
            const drained = await postSelfProvision({ signedTransactionInfo: "x" });
            expect(drained.status).toBe(429);
        });
    });
});

// NOTE: this block used to exercise /StopMonitoring, but that endpoint now proxies to the
// AWS Lambda reader (see gtfsrt/proxy.ts) and no longer goes through the generic
// hot-cache/rate-limit proxy path below. /StopTimetable still does, so it now stands
// in for exercising that shared mechanism (Cache API HIT/STALE + rate-limit-after-cache).
// Its TTLs come from TIMETABLE_TTL (24h fresh / 7d stale) rather than DEFAULT_TTL, hence the
// different fetchedAtMs offsets vs. before.
describe("cacheable SIRI endpoints (Cache API + rate-limit-after-cache)", () => {
    const SM_TOKEN = "cache-test-token";
    const SM_URL = "https://example.com/StopTimetable?operatorref=SF&monitoringref=99999";
    // upstream URL the worker builds (params in the order buildUpstreamUrl emits them, then api_key, then format)
    const UPSTREAM = "https://api.511.org/transit/stoptimetable?operatorref=SF&monitoringref=99999&api_key=test-511-key&format=json";

    async function proxyKey(token: string): Promise<string> {
        const tokenHash = await sha256Hex(token);
        const idHash = (await sha256Hex(tokenHash)).slice(0, 16);
        const bucket = String(Math.floor(Date.now() / 1000 / PROXY_RATE_LIMIT.windowSeconds));
        return `ratelimit:proxy-token:${idHash}:${bucket}`;
    }

    async function seedCache(fetchedAtMs: number) {
        const res = new Response("<Siri>cached</Siri>", {
            headers: {
                "Content-Type": "application/xml; charset=utf-8",
                "Cache-Control": "max-age=21600",
                "X-Cached-At-Ms": String(fetchedAtMs),
                "X-Origin-Status": "200",
                "X-Origin-Content-Type": "application/xml; charset=utf-8",
            },
        });
        await caches.default.put(new Request(UPSTREAM), res);
    }

    beforeAll(async () => {
        const hash = await sha256Hex(SM_TOKEN);
        await (env as unknown as { CLIENT_TOKENS: KVNamespace }).CLIENT_TOKENS.put(
            hash, JSON.stringify({ label: "cache-test", createdAt: "2026-06-01T00:00:00Z" }),
        );
    });

    beforeEach(async () => {
        await caches.default.delete(new Request(UPSTREAM));
        await (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE.delete(await proxyKey(SM_TOKEN));
    });

    it("serves a fresh cache HIT even when the data bucket is full (hit does not require budget)", async () => {
        await seedCache(Date.now()); // fresh (< 24h)
        await (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE.put(
            await proxyKey(SM_TOKEN), String(PROXY_RATE_LIMIT.maxRequests), { expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2 },
        );
        const res = await SELF.fetch(SM_URL, { headers: { "X-App-Token": SM_TOKEN } });
        expect(res.status).toBe(200);
        expect(res.headers.get("X-Cache-Status")).toBe("HIT");
    });

    it("serves STALE (not 429) when rate-limited but a stale cache entry exists", async () => {
        await seedCache(Date.now() - 25 * 60 * 60 * 1000); // stale (> 24h fresh, < 7d stale)
        await (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE.put(
            await proxyKey(SM_TOKEN), String(PROXY_RATE_LIMIT.maxRequests), { expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2 },
        );
        const res = await SELF.fetch(SM_URL, { headers: { "X-App-Token": SM_TOKEN } });
        expect(res.status).toBe(200);
        expect(res.headers.get("X-Cache-Status")).toBe("STALE");
    });

    it("returns 429 when rate-limited and no cache exists", async () => {
        await (env as unknown as { TRANSIT_CACHE: KVNamespace }).TRANSIT_CACHE.put(
            await proxyKey(SM_TOKEN), String(PROXY_RATE_LIMIT.maxRequests), { expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2 },
        );
        const res = await SELF.fetch(SM_URL, { headers: { "X-App-Token": SM_TOKEN } });
        expect(res.status).toBe(429);
    });
});

describe("GET /healthz/appstore", () => {
    afterEach(() => {
        vi.unstubAllGlobals();
    });

    it("returns 401 without an Authorization header", async () => {
        const res = await SELF.fetch("https://example.com/healthz/appstore");
        expect(res.status).toBe(401);
    });

    it("returns 401 with the wrong bearer token", async () => {
        const res = await SELF.fetch("https://example.com/healthz/appstore", {
            headers: { Authorization: "Bearer wrong-token" },
        });
        expect(res.status).toBe(401);
    });

    it("returns 200 with ok:true when both checks pass", async () => {
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(null, { status: 404 })));

        const res = await SELF.fetch("https://example.com/healthz/appstore", {
            headers: { Authorization: "Bearer test-healthcheck-token" },
        });

        expect(res.status).toBe(200);
        const body = (await res.json()) as { ok: boolean; checks: Record<string, { ok: boolean }> };
        expect(body.ok).toBe(true);
        expect(body.checks.appleJwsVerifier.ok).toBe(true);
        expect(body.checks.appStoreAuth.ok).toBe(true);
    });

    it("returns 503 with ok:false when the App Store auth check fails", async () => {
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(null, { status: 401 })));

        const res = await SELF.fetch("https://example.com/healthz/appstore", {
            headers: { Authorization: "Bearer test-healthcheck-token" },
        });

        expect(res.status).toBe(503);
        const body = (await res.json()) as { ok: boolean; checks: Record<string, { ok: boolean }> };
        expect(body.ok).toBe(false);
        expect(body.checks.appStoreAuth.ok).toBe(false);
    });

    it("returns 503 with ok:false when APPSTORE_APP_APPLE_ID is not configured", async () => {
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(null, { status: 404 })));

        const testEnv = env as unknown as { APPSTORE_APP_APPLE_ID: string };
        const original = testEnv.APPSTORE_APP_APPLE_ID;
        testEnv.APPSTORE_APP_APPLE_ID = "";
        try {
            const res = await SELF.fetch("https://example.com/healthz/appstore", {
                headers: { Authorization: "Bearer test-healthcheck-token" },
            });

            expect(res.status).toBe(503);
            const body = (await res.json()) as { ok: boolean; checks: Record<string, { ok: boolean }> };
            expect(body.ok).toBe(false);
            expect(body.checks.appleJwsVerifier.ok).toBe(false);
        } finally {
            testEnv.APPSTORE_APP_APPLE_ID = original;
        }
    });

    it("returns 503 with ok:false when the App Store auth check throws", async () => {
        vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network error")));

        const res = await SELF.fetch("https://example.com/healthz/appstore", {
            headers: { Authorization: "Bearer test-healthcheck-token" },
        });

        expect(res.status).toBe(503);
        const body = (await res.json()) as { ok: boolean; checks: Record<string, { ok: boolean; error?: string }> };
        expect(body.ok).toBe(false);
        expect(body.checks.appStoreAuth.ok).toBe(false);
        expect(body.checks.appStoreAuth.error).toBe("App Store auth check failed");
    });

    it("returns 405 for non-GET requests", async () => {
        const res = await SELF.fetch("https://example.com/healthz/appstore", {
            method: "POST",
            headers: { Authorization: "Bearer test-healthcheck-token" },
        });

        expect(res.status).toBe(405);
    });
});
