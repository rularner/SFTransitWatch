import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const envVarName = "TRANSIT_CACHE_KV_ID";
const kvId = process.env[envVarName]?.trim();

if (!kvId) {
	console.error(`Missing required environment variable: ${envVarName}`);
	process.exit(1);
}

const wranglerPath = resolve(process.cwd(), "wrangler.jsonc");
const config = readFileSync(wranglerPath, "utf8");
const updated = config.replace(/"id"\s*:\s*"[^"]*"/, `"id": "${kvId}"`);

if (updated === config) {
	console.error("Could not locate kv_namespaces id field in wrangler.jsonc");
	process.exit(1);
}

writeFileSync(wranglerPath, updated, "utf8");
console.log("Updated TRANSIT_CACHE KV namespace id in wrangler.jsonc");
