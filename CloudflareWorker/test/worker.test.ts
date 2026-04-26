/// <reference path="../node_modules/@cloudflare/vitest-pool-workers/types/cloudflare-test.d.ts" />
import { describe, it, expect } from "vitest";
import { SELF } from "cloudflare:test";

const VALID_TOKEN = "test-token";

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
