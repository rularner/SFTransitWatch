// The deploy entrypoint wrangler.jsonc's "main" points to.
//
// src/index.ts exports several internal helpers (constants, authorizeClient,
// parseStopsFromApi, etc.) purely so test/worker.test.ts can unit-test them
// directly — but Cloudflare Workers' modules format treats every named export
// of the *entry* module as a candidate "named entrypoint" and requires each
// one to be a function/class/ExportedHandler. A plain `export const` like
// STALE_TTL_SECONDS fails that check and crashes the Worker at startup
// ("Incorrect type for map entry '...': the provided value is not of type
// 'function or ExportedHandler'"), confirmed locally via `wrangler dev`.
//
// Re-exporting only `default` here — instead of pointing "main" at index.ts
// directly — keeps index.ts's test-only exports intact for vitest while
// presenting a clean single-export surface to the real deploy.
export { default } from "./index";
