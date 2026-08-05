#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";

const REQUIRED_VARS = [
    ["TRANSIT_CACHE_KV_ID", "__TRANSIT_CACHE_KV_ID__"],
    ["CLIENT_TOKENS_KV_ID", "__CLIENT_TOKENS_KV_ID__"],
    ["WORKER_HOSTNAME", "__WORKER_HOSTNAME__"],
    ["APPSTORE_APP_APPLE_ID", "__APPSTORE_APP_APPLE_ID__"],
];

const values = {};
for (const [envVar, placeholder] of REQUIRED_VARS) {
    const value = process.env[envVar]?.trim();
    if (!value) {
        console.error(`Missing required environment variable: ${envVar}`);
        process.exit(1);
    }
    values[placeholder] = value;
}

const source = "wrangler.jsonc";
const output = ".wrangler.generated.jsonc";
let config = readFileSync(source, "utf8");

for (const [, placeholder] of REQUIRED_VARS) {
    if (!config.includes(placeholder)) {
        console.error(`Missing ${placeholder} placeholder in wrangler.jsonc`);
        process.exit(1);
    }
    config = config.replaceAll(placeholder, values[placeholder]);
}

writeFileSync(output, config);
console.log(`Generated ${output} with ${REQUIRED_VARS.map(([envVar]) => envVar).join(", ")}`);
