import { describe, it, expect } from "vitest";
import { encodeSnapshot, decodeSnapshot } from "../../src/gtfsrt/snapshotCodec";
import type { ArrivalsIndex } from "../../src/gtfsrt/indexBuilder";

describe("snapshotCodec", () => {
  it("round-trips an index and fetchedAtMs", () => {
    const index: ArrivalsIndex = {
      SF: { "16393": [{ lineRef: "44", directionRef: "IB", expectedArrival: 200, onward: [] }] },
    };
    const body = encodeSnapshot(index, 12345);
    expect(decodeSnapshot(body)).toEqual({ fetchedAtMs: 12345, index });
  });
});
