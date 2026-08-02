import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import type { S3Client } from "@aws-sdk/client-s3";
import { toStopMonitoringJson } from "../gtfsrt/siri";
import { getSnapshotObject } from "../gtfsrt/s3Snapshot";
import { decodeSnapshot, SNAPSHOT_KEY, type StoredSnapshot } from "../gtfsrt/snapshotCodec";

const LOCAL_CACHE_MS = 30_000;

// Stop names are NOT resolved here — the reader emits StopPointName == StopPointRef and the
// Worker resolves real names afterward from its own stops:${agency} KV cache. Giving this
// Lambda its own copy of that data (or Cloudflare credentials to read it) isn't worth it: the
// Worker-side resolution is bounded by maxOnward (<=15 entries), nothing like the full regional
// decode this migration exists to move off the request path.
export function createReader(
  s3: S3Client,
  bucket: string,
  internalKey: string,
  clock: () => number = Date.now,
) {
  let cached: StoredSnapshot | null = null;
  let cachedAt = 0;

  return async function reader(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
    if ((event.headers?.["x-internal-key"] ?? "") !== internalKey) {
      return { statusCode: 401, body: JSON.stringify({ error: "Unauthorized" }) };
    }

    const params = new URLSearchParams(event.rawQueryString ?? "");
    const agency = params.get("agency") ?? "SF";
    const stopCode = params.get("stopCode") ?? "";
    const maxOnwardParam = Number(params.get("MaximumNumberOfCallsOnwards") ?? "10");
    const maxOnward = Number.isFinite(maxOnwardParam) ? maxOnwardParam : 10;

    const now = clock();
    if (cached === null || now - cachedAt >= LOCAL_CACHE_MS) {
      try {
        const body = await getSnapshotObject(s3, bucket, SNAPSHOT_KEY);
        cached = body === null ? null : decodeSnapshot(body);
        cachedAt = now;
      } catch (error) {
        // Keep serving whatever `cached` already holds (possibly null, if this is the very
        // first request) and deliberately don't update cachedAt — the next request retries
        // immediately instead of waiting out the rest of the 30s window on a bad read.
        console.error("GTFS-RT snapshot reload from S3 failed:", error);
      }
    }

    const visits = cached?.index[agency]?.[stopCode] ?? [];
    const json = toStopMonitoringJson({ stopCode, visits, maxOnward, stopName: (id) => id });
    const headers: Record<string, string> = { "content-type": "application/json; charset=utf-8" };
    if (cached !== null) {
      headers["x-snapshot-age-ms"] = String(Math.max(0, clock() - cached.fetchedAtMs));
    }
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify(json),
    };
  };
}
