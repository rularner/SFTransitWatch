import { defineConfig } from "wrangler";

const KV_ID = process.env.TRANSIT_CACHE_KV_ID || "must_specify_transit_cache_id";

export default defineConfig({
  name: "sftransitwatch",
  main: "src/index.ts",
  compatibility_date: "2026-04-20",
  kv_namespaces: [
    {
      binding: "TRANSIT_CACHE",
      id: KV_ID,
    },
  ]
});
