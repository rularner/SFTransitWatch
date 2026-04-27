# Cloudflare Worker Setup

This Worker proxies and caches 511.org requests for the iPhone and Apple Watch apps.

## Required Cloudflare Git Build Settings

When using Cloudflare's Git integration, set:

- **Build command**: `cd CloudflareWorker && npm run deploy`
- **Environment variable**: `TRANSIT_CACHE_KV_ID=<your_kv_namespace_id>`

The deploy script generates `.wrangler.generated.jsonc` from `wrangler.jsonc`, replacing the `__TRANSIT_CACHE_KV_ID__` placeholder before running Wrangler deploy.

## Local Development

Use the same variable locally:

- `cd CloudflareWorker`
- `TRANSIT_CACHE_KV_ID=<your_kv_namespace_id> npm run dev`

Type generation also needs the variable:

- `TRANSIT_CACHE_KV_ID=<your_kv_namespace_id> npm run cf-typegen`

## Notes

- `TRANSIT_CACHE_KV_ID` is required for `npm run deploy`, `npm run dev`, and `npm run cf-typegen`.
- `.wrangler.generated.jsonc` is generated at runtime and is gitignored.
