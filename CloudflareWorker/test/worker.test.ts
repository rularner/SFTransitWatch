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
