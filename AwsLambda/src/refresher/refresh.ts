import type { S3Client } from "@aws-sdk/client-s3";
import { decodeTripUpdates } from "../gtfsrt/decode";
import { buildArrivalsIndex } from "../gtfsrt/indexBuilder";
import { gunzipIfNeeded } from "../gtfsrt/gunzip";
import { putSnapshotObject } from "../gtfsrt/s3Snapshot";
import { encodeSnapshot, SNAPSHOT_KEY } from "../gtfsrt/snapshotCodec";

const UPSTREAM = "https://api.511.org/transit/tripupdates";

// Called only from the scheduled handler in index.ts, never from a request path. Any failure —
// network error, non-OK upstream, corrupt protobuf — is caught and logged here; the prior S3
// object (if any) is left in place for the reader Lambda to keep serving. Never throws.
export async function refreshSnapshot(
  s3: S3Client,
  bucket: string,
  api511Key: string,
  now: number,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  try {
    const u = new URL(UPSTREAM);
    u.searchParams.set("agency", "RG");
    u.searchParams.set("api_key", api511Key);
    const res = await fetchImpl(u.toString());
    if (!res.ok) {
      console.error(`GTFS-RT upstream error refreshing RG snapshot: HTTP ${res.status}`);
      return;
    }
    const bytes = gunzipIfNeeded(new Uint8Array(await res.arrayBuffer()));
    const index = buildArrivalsIndex(decodeTripUpdates(bytes));
    await putSnapshotObject(s3, bucket, SNAPSHOT_KEY, encodeSnapshot(index, now));
  } catch (error) {
    console.error("GTFS-RT snapshot refresh failed:", error);
  }
}
