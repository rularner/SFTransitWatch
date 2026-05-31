/// <reference path="../node_modules/@cloudflare/vitest-pool-workers/types/cloudflare-test.d.ts" />
import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { SELF, env } from "cloudflare:test";
import { sha256Hex, parseStopsFromApi, distanceMeters, PROXY_RATE_LIMIT } from "../src/index";

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

    it("filters stops by proximity when lat/lon and radius provided", async () => {
        // 200 m around Market & 4th — should include Market & 5th but not Mission & 24th
        const res = await SELF.fetch(
            "https://example.com/Stops?agency=SF&lat=37.7844&lon=-122.4062&radius=200",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).toBe(200);
        const body = (await res.json()) as StopsBody;
        const ids = body.Contents.dataObjects.ScheduledStopPoint.map((s) => s.id);
        expect(ids).toContain("15725");
        expect(ids).toContain("15726");
        expect(ids).not.toContain("16000");
    });

    it("also accepts latitude/longitude param names", async () => {
        const res = await SELF.fetch(
            "https://example.com/Stops?agency=SF&latitude=37.7844&longitude=-122.4062&radius=200",
            { headers: { "X-App-Token": VALID_TOKEN } },
        );
        expect(res.status).toBe(200);
        const body = (await res.json()) as StopsBody;
        const ids = body.Contents.dataObjects.ScheduledStopPoint.map((s) => s.id);
        expect(ids).toContain("15725");
        expect(ids).not.toContain("16000");
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

    it("returns 429 when the per-token request count has reached the limit", async () => {
        const key = await rateLimitKeyForToken(RL_TOKEN);
        await CACHE().put(key, String(PROXY_RATE_LIMIT.maxRequests), {
            expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2,
        });

        const res = await SELF.fetch("https://example.com/Stops?agency=SF", {
            headers: { "X-App-Token": RL_TOKEN },
        });
        expect(res.status).toBe(429);
    });

    it("includes Retry-After header in the 429 response", async () => {
        const key = await rateLimitKeyForToken(RL_TOKEN);
        await CACHE().put(key, String(PROXY_RATE_LIMIT.maxRequests), {
            expirationTtl: PROXY_RATE_LIMIT.windowSeconds * 2,
        });

        const res = await SELF.fetch("https://example.com/Stops?agency=SF", {
            headers: { "X-App-Token": RL_TOKEN },
        });
        expect(res.headers.get("Retry-After")).toBe(String(PROXY_RATE_LIMIT.windowSeconds));
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
    const TEST_ENV = env as unknown as {
        CLIENT_TOKENS: KVNamespace;
        TEST_PROVISION_PRIVATE_KEY: string;
        TRANSIT_CACHE: KVNamespace;
    };

    let testPrivateKey: CryptoKey;

    beforeEach(async () => {
        const { keys } = await TEST_ENV.TRANSIT_CACHE.list({ prefix: "ratelimit:" });
        await Promise.all(keys.map((k) => TEST_ENV.TRANSIT_CACHE.delete(k.name)));
    });

    async function signJWT(
        payload: Record<string, unknown>,
        overrideKey?: CryptoKey,
    ): Promise<string> {
        const key = overrideKey ?? testPrivateKey;
        const header = { alg: "ES256", typ: "JWT" };
        const b64url = (data: ArrayBuffer | string) => {
            const bytes =
                typeof data === "string"
                    ? new TextEncoder().encode(data)
                    : new Uint8Array(data);
            let str = "";
            for (const b of bytes) str += String.fromCharCode(b);
            return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
        };
        const encodedHeader = b64url(JSON.stringify(header));
        const encodedPayload = b64url(JSON.stringify(payload));
        const signingInput = `${encodedHeader}.${encodedPayload}`;
        const sig = await crypto.subtle.sign(
            { name: "ECDSA", hash: "SHA-256" },
            key,
            new TextEncoder().encode(signingInput),
        );
        return `${signingInput}.${b64url(sig)}`;
    }

    function validPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
        const now = Math.floor(Date.now() / 1000);
        return {
            iss: "org.larner.SFTransitWatch",
            install_id: "aabbccdd-1234-5678-abcd-ef0123456789",
            platform: "ios",
            app_version: "1.0.0",
            iat: now,
            exp: now + 60,
            ...overrides,
        };
    }

    beforeAll(async () => {
        const pkcs8 = Uint8Array.from(
            atob(TEST_ENV.TEST_PROVISION_PRIVATE_KEY),
            (c) => c.charCodeAt(0),
        );
        testPrivateKey = await crypto.subtle.importKey(
            "pkcs8",
            pkcs8,
            { name: "ECDSA", namedCurve: "P-256" },
            false,
            ["sign"],
        );
    });

    it("returns 400 when body is missing", async () => {
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
        });
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

    it("returns 400 when jwt field is absent", async () => {
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ other: "field" }),
        });
        expect(res.status).toBe(400);
    });

    it("returns 401 when JWT signature is invalid", async () => {
        const wrongKeyPair = await crypto.subtle.generateKey(
            { name: "ECDSA", namedCurve: "P-256" },
            true,
            ["sign", "verify"],
        );
        const jwt = await signJWT(validPayload(), wrongKeyPair.privateKey);
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ jwt }),
        });
        expect(res.status).toBe(401);
    });

    it("returns 401 when exp is in the past", async () => {
        const now = Math.floor(Date.now() / 1000);
        const jwt = await signJWT(validPayload({ iat: now - 120, exp: now - 60 }));
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ jwt }),
        });
        expect(res.status).toBe(401);
    });

    it("returns 401 when iss does not match the expected bundle ID", async () => {
        const jwt = await signJWT(validPayload({ iss: "com.evil.app" }));
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ jwt }),
        });
        expect(res.status).toBe(401);
    });

    it("returns 200 with a token for a valid JWT", async () => {
        const jwt = await signJWT(validPayload());
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ jwt }),
        });
        expect(res.status).toBe(200);
        const body = (await res.json()) as { token: string };
        expect(typeof body.token).toBe("string");
        expect(body.token.length).toBeGreaterThan(8);
    });

    it("stores the token in CLIENT_TOKENS under sha256(token)", async () => {
        const jwt = await signJWT(validPayload({ install_id: "store-test-id", platform: "ios", app_version: "1.0.0" }));
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ jwt }),
        });
        const { token } = (await res.json()) as { token: string };
        const hash = await sha256Hex(token);
        const stored = (await TEST_ENV.CLIENT_TOKENS.get(hash, "json")) as { label: string } | null;
        expect(stored).not.toBeNull();
        expect(stored!.label).toContain("self-prov");
        expect(stored!.label).toContain("ios");
    });

    it("label contains the platform and first 8 chars of install_id", async () => {
        const installId = "12345678-abcd-ef01-2345-678901234567";
        const jwt = await signJWT(validPayload({ install_id: installId, platform: "watchos", app_version: "2.0.0" }));
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ jwt }),
        });
        const { token } = (await res.json()) as { token: string };
        const hash = await sha256Hex(token);
        const stored = (await TEST_ENV.CLIENT_TOKENS.get(hash, "json")) as { label: string } | null;
        expect(stored!.label).toBe("self-prov:watchos:12345678:2.0.0");
    });

    it("is accessible without an X-App-Token header", async () => {
        const jwt = await signJWT(validPayload({ install_id: "no-token-test-id" }));
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ jwt }),
        });
        expect(res.status).not.toBe(401);
    });

    it("returns 405 for non-POST methods", async () => {
        const res = await SELF.fetch("https://example.com/self-provision", {
            method: "GET",
        });
        expect(res.status).toBe(405);
    });
});
