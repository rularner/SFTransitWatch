import type { ArrivalsIndex } from "./indexBuilder";

// Shared, dependency-free constant used by both the refresher (writes) and the reader (reads),
// so the reader's bundle doesn't have to transitively pull in refresher/decode/indexBuilder code.
export const SNAPSHOT_KEY = "snapshots/RG.json";

export interface StoredSnapshot {
  fetchedAtMs: number;
  index: ArrivalsIndex;
}

export function encodeSnapshot(index: ArrivalsIndex, fetchedAtMs: number): string {
  return JSON.stringify({ fetchedAtMs, index } satisfies StoredSnapshot);
}

export function decodeSnapshot(body: string): StoredSnapshot {
  return JSON.parse(body) as StoredSnapshot;
}
