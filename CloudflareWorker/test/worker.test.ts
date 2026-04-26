/// <reference path="../node_modules/@cloudflare/vitest-pool-workers/types/cloudflare-test.d.ts" />
import { describe, it, expect } from "vitest";
import { SELF } from "cloudflare:test";

describe("worker harness", () => {
	it("responds to OPTIONS preflight without a token", async () => {
		const res = await SELF.fetch("https://example.com/StopMonitoring", {
			method: "OPTIONS",
		});
		expect(res.status).toBe(204);
	});
});
