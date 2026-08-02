import { describe, it, expect } from "vitest";
import { gzipSync } from "node:zlib";
import { gunzipIfNeeded } from "../../src/gtfsrt/gunzip";

describe("gunzipIfNeeded", () => {
  it("returns plain (non-gzipped) bytes unchanged", () => {
    const plain = new Uint8Array([1, 2, 3, 4]);
    expect(gunzipIfNeeded(plain)).toEqual(plain);
  });

  it("decompresses a gzip-magic-byte buffer", () => {
    const original = new TextEncoder().encode("hello gtfs-rt");
    const compressed = new Uint8Array(gzipSync(Buffer.from(original)));
    expect(compressed[0]).toBe(0x1f);
    expect(compressed[1]).toBe(0x8b);

    const result = gunzipIfNeeded(compressed);
    expect(new TextDecoder().decode(result)).toBe("hello gtfs-rt");
  });
});
