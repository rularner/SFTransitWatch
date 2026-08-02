import type { ArrivalsIndex } from "./indexBuilder";

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
