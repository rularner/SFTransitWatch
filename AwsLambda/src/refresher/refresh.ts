import type { S3Client } from "@aws-sdk/client-s3";
import type { SNSClient } from "@aws-sdk/client-sns";
import { PublishCommand } from "@aws-sdk/client-sns";
import { decodeTripUpdates } from "../gtfsrt/decode";
import { buildArrivalsIndex } from "../gtfsrt/indexBuilder";
import { gunzipIfNeeded } from "../gtfsrt/gunzip";
import { getSnapshotObject, putSnapshotObject } from "../gtfsrt/s3Snapshot";
import { decodeSnapshot, encodeSnapshot, SNAPSHOT_KEY } from "../gtfsrt/snapshotCodec";

const UPSTREAM = "https://api.511.org/transit/tripupdates";

// BART is closed and other Bay Area agencies run reduced/no service in this window, so there's
// nothing to gain from polling every 2 minutes. Pacific-local, not UTC: see the TODO.md entry
// this implements for why that rules out a second EventBridge cron schedule (no timezone param,
// manual DST math). Intl.DateTimeFormat with an IANA zone handles DST automatically.
const QUIET_HOUR_START_PACIFIC = 1; // 1am
const QUIET_HOUR_END_PACIFIC = 5; // 5am, exclusive
const QUIET_WINDOW_INTERVAL_MS = 15 * 60 * 1000;

// Throttle so a sustained 511 outage/quota exhaustion doesn't page every 2 minutes.
const QUOTA_ALERT_COOLDOWN_MS = 6 * 60 * 60 * 1000;
const QUOTA_ALERT_STATE_KEY = "state/last-quota-alert-ms.txt";

function isQuietHourPacific(nowMs: number): boolean {
  // hourCycle "h23" avoids the "24" some ICU builds return for midnight under hour12:false.
  const hour = Number(
    new Intl.DateTimeFormat("en-US", { timeZone: "America/Los_Angeles", hour: "numeric", hourCycle: "h23" }).format(
      nowMs,
    ),
  );
  return hour >= QUIET_HOUR_START_PACIFIC && hour < QUIET_HOUR_END_PACIFIC;
}

async function alertQuotaExceededIfDue(
  s3: S3Client,
  bucket: string,
  snsClient: SNSClient,
  alertTopicArn: string,
  nowMs: number,
): Promise<void> {
  const lastAlertRaw = await getSnapshotObject(s3, bucket, QUOTA_ALERT_STATE_KEY);
  const lastAlertMs = lastAlertRaw ? Number(lastAlertRaw) : 0;
  if (nowMs - lastAlertMs < QUOTA_ALERT_COOLDOWN_MS) return;

  await putSnapshotObject(s3, bucket, QUOTA_ALERT_STATE_KEY, String(nowMs));
  await snsClient.send(
    new PublishCommand({
      TopicArn: alertTopicArn,
      Subject: "SFTransitWatch: 511.org API quota exceeded",
      Message:
        "The GTFS-RT refresher got HTTP 429 from api.511.org/transit/tripupdates — the free-tier " +
        "daily quota (1,000 req/day) has been hit. The RG snapshot will keep serving cached/stale " +
        "data to the reader Lambda until 511 resets the quota (typically midnight Pacific). This " +
        "alert won't repeat for 6 hours.",
    }),
  );
}

// Called only from the scheduled handler in index.ts, never from a request path. Any failure —
// network error, non-OK upstream, corrupt protobuf — is caught and logged here; the prior S3
// object (if any) is left in place for the reader Lambda to keep serving. Never throws.
export async function refreshSnapshot(
  s3: S3Client,
  bucket: string,
  api511Key: string,
  now: number,
  fetchImpl: typeof fetch = fetch,
  snsClient?: SNSClient,
  alertTopicArn?: string,
): Promise<void> {
  try {
    if (isQuietHourPacific(now)) {
      const existing = await getSnapshotObject(s3, bucket, SNAPSHOT_KEY);
      if (existing && now - decodeSnapshot(existing).fetchedAtMs < QUIET_WINDOW_INTERVAL_MS) {
        return; // cached snapshot is still fresh enough for the widened quiet-hours interval
      }
    }

    const u = new URL(UPSTREAM);
    u.searchParams.set("agency", "RG");
    u.searchParams.set("api_key", api511Key);
    const res = await fetchImpl(u.toString());
    if (!res.ok) {
      console.error(`GTFS-RT upstream error refreshing RG snapshot: HTTP ${res.status}`);
      if (res.status === 429 && snsClient && alertTopicArn) {
        await alertQuotaExceededIfDue(s3, bucket, snsClient, alertTopicArn, now);
      }
      return;
    }
    const bytes = gunzipIfNeeded(new Uint8Array(await res.arrayBuffer()));
    const index = buildArrivalsIndex(decodeTripUpdates(bytes));
    await putSnapshotObject(s3, bucket, SNAPSHOT_KEY, encodeSnapshot(index, now));
  } catch (error) {
    console.error("GTFS-RT snapshot refresh failed:", error);
  }
}
