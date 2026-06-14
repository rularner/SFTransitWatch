/// <reference path="../node_modules/@cloudflare/vitest-pool-workers/types/cloudflare-test.d.ts" />
import { describe, it, expect, afterEach, vi } from "vitest";
import { env } from "cloudflare:test";
import { verifySubscription, type AppStoreEnv } from "../src/appstore";

const TEST_ENV = env as unknown as AppStoreEnv;

function b64url(bytes: Uint8Array): string {
    let str = "";
    for (const b of bytes) str += String.fromCharCode(b);
    return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function fakeSignedTransactionInfo(payload: Record<string, unknown>): string {
    const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256" })));
    const body = b64url(new TextEncoder().encode(JSON.stringify(payload)));
    return `${header}.${body}.fake-signature`;
}

function appStoreResponse(lastTransactions: Array<{ status: number; signedTransactionInfo: string }>): Response {
    return new Response(JSON.stringify({ data: [{ lastTransactions }] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
    });
}

describe("verifySubscription", () => {
    afterEach(() => {
        vi.unstubAllGlobals();
    });

    it("returns active for status 1 with a future expiresDate", async () => {
        const expiresAtMs = Date.now() + 30 * 24 * 60 * 60 * 1000;
        const jws = fakeSignedTransactionInfo({ expiresDate: expiresAtMs });
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(appStoreResponse([{ status: 1, signedTransactionInfo: jws }])));

        const result = await verifySubscription(TEST_ENV, "1000000000000001");
        expect(result).toEqual({ active: true, expiresAtMs });
    });

    it("returns active for status 4 (billing grace period) with a future expiresDate", async () => {
        const expiresAtMs = Date.now() + 24 * 60 * 60 * 1000;
        const jws = fakeSignedTransactionInfo({ expiresDate: expiresAtMs });
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(appStoreResponse([{ status: 4, signedTransactionInfo: jws }])));

        const result = await verifySubscription(TEST_ENV, "1000000000000001");
        expect(result).toEqual({ active: true, expiresAtMs });
    });

    it("returns inactive for status 2 (expired)", async () => {
        const jws = fakeSignedTransactionInfo({ expiresDate: Date.now() - 1000 });
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(appStoreResponse([{ status: 2, signedTransactionInfo: jws }])));

        const result = await verifySubscription(TEST_ENV, "1000000000000001");
        expect(result).toEqual({ active: false });
    });

    it("returns inactive for status 5 (revoked) even with a future expiresDate", async () => {
        const jws = fakeSignedTransactionInfo({ expiresDate: Date.now() + 1000 });
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(appStoreResponse([{ status: 5, signedTransactionInfo: jws }])));

        const result = await verifySubscription(TEST_ENV, "1000000000000001");
        expect(result).toEqual({ active: false });
    });

    it("retries against the sandbox host when production returns 404", async () => {
        const expiresAtMs = Date.now() + 30 * 24 * 60 * 60 * 1000;
        const jws = fakeSignedTransactionInfo({ expiresDate: expiresAtMs });
        const fetchMock = vi
            .fn()
            .mockResolvedValueOnce(new Response(null, { status: 404 }))
            .mockResolvedValueOnce(appStoreResponse([{ status: 1, signedTransactionInfo: jws }]));
        vi.stubGlobal("fetch", fetchMock);

        const result = await verifySubscription(TEST_ENV, "1000000000000001");
        expect(result).toEqual({ active: true, expiresAtMs });
        expect(fetchMock).toHaveBeenCalledTimes(2);
        expect(String(fetchMock.mock.calls[1][0])).toContain("storekit-sandbox.itunes.apple.com");
    });

    it("returns inactive when Apple returns no transactions", async () => {
        vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: [] }), { status: 200 })));

        const result = await verifySubscription(TEST_ENV, "1000000000000001");
        expect(result).toEqual({ active: false });
    });
});
