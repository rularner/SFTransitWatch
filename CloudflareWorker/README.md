# Cloudflare Worker Setup

This Worker proxies and caches 511.org requests for the iPhone and Apple Watch apps.

## Required Cloudflare Git Build Settings

When using Cloudflare's Git integration, set:

- **Build command**: `cd CloudflareWorker && npm run deploy`
- **Environment variables**:
  - `TRANSIT_CACHE_KV_ID=<your_transit_cache_namespace_id>`
  - `CLIENT_TOKENS_KV_ID=<your_client_tokens_namespace_id>`

The deploy script generates `.wrangler.generated.jsonc` from `wrangler.jsonc`,
substituting both `__TRANSIT_CACHE_KV_ID__` and `__CLIENT_TOKENS_KV_ID__`
before running Wrangler deploy.

## Local Development

Use the same variables locally:

- `cd CloudflareWorker`
- `TRANSIT_CACHE_KV_ID=<id> CLIENT_TOKENS_KV_ID=<id> npm run dev`

Type generation also needs both:

- `TRANSIT_CACHE_KV_ID=<id> CLIENT_TOKENS_KV_ID=<id> npm run cf-typegen`

## Issuing client tokens

Each device on the allowlist gets its own random token. The worker stores
only the SHA-256 hash, so the raw token never touches disk on the worker
side. The issuer script bundles the worker's public URL into the same
link, so a single paste/tap configures both URL and token on the device:

```bash
WORKER_URL=https://your-worker.workers.dev ./scripts/issue-token.sh <label>
```

The printed bootstrap link goes to the device via Messages/Mail.
- **iOS**: paste it into Settings → Worker proxy.
- **watchOS**: tap the link in the message — the watch app accepts it via
  the `/wt` universal link handler.

Revoke a token by deleting its hash from KV:
```bash
npx wrangler kv key delete --binding CLIENT_TOKENS <hash>
```

## Notes

- `TRANSIT_CACHE_KV_ID` and `CLIENT_TOKENS_KV_ID` are required for `npm run deploy`, `npm run dev`, and `npm run cf-typegen`.
- `.wrangler.generated.jsonc` is generated at runtime and is gitignored.
