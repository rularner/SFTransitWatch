import { defineConfig } from "vitest/config";
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";

export default defineConfig({
	plugins: [
		cloudflareTest({
			wrangler: { configPath: "./wrangler.jsonc" },
			miniflare: {
				bindings: {
					API_511_KEY: "test-511-key",
				},
				kvNamespaces: ["CLIENT_TOKENS", "TRANSIT_CACHE"],
			},
		}),
	],
});
