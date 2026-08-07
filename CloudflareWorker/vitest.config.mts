import { defineConfig } from "vitest/config";
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";

const appStoreKeyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
);
const appStorePkcs8 = await crypto.subtle.exportKey("pkcs8", appStoreKeyPair.privateKey);

const toBase64 = (buf: ArrayBuffer) =>
    Buffer.from(buf).toString("base64");

export default defineConfig({
    plugins: [
        cloudflareTest({
            wrangler: { configPath: "./wrangler.jsonc" },
            miniflare: {
                bindings: {
                    API_511_KEY: "test-511-key",
                    APPSTORE_APP_APPLE_ID: "1234567890",
                    APPSTORE_KEY_ID: "test-key-id",
                    APPSTORE_ISSUER_ID: "test-issuer-id",
                    APPSTORE_PRIVATE_KEY: toBase64(appStorePkcs8),
                    APPSTORE_BUNDLE_ID: "org.larner.SFTransitWatch",
                    HEALTHCHECK_TOKEN: "test-healthcheck-token",
                    GTFSRT_READER_URL: "https://reader.example.com/",
                    GTFSRT_INTERNAL_KEY: "test-internal-key",
                },
                kvNamespaces: ["CLIENT_TOKENS", "TRANSIT_CACHE"],
            },
        }),
    ],
});
