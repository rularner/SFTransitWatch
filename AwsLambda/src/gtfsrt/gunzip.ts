import { gunzipSync } from "node:zlib";

export function gunzipIfNeeded(raw: Uint8Array): Uint8Array {
  const gzipped = raw[0] === 0x1f && raw[1] === 0x8b;
  if (!gzipped) return raw;
  return new Uint8Array(gunzipSync(raw));
}
