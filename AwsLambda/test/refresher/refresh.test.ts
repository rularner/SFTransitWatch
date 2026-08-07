import { describe, it, expect, vi } from "vitest";
import { gzipSync } from "node:zlib";
import { Readable } from "node:stream";
import type { S3Client } from "@aws-sdk/client-s3";
import { PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import type { SNSClient } from "@aws-sdk/client-sns";
import { PublishCommand } from "@aws-sdk/client-sns";
import { refreshSnapshot } from "../../src/refresher/refresh";
import { decodeSnapshot, encodeSnapshot, SNAPSHOT_KEY } from "../../src/gtfsrt/snapshotCodec";
import { writeVarint, writeField, writeLenField, writeStringField } from "../../src/gtfsrt/protobuf";

function stopTimeEvent(t: number) { return writeField(2, 0, writeVarint(t)); }
function stu(seq: number, id: string, t: number) {
  return [...writeField(1, 0, writeVarint(seq)), ...writeLenField(2, stopTimeEvent(t)), ...writeStringField(4, id)];
}
function feedBytes(nowSec: number): Uint8Array {
  const trip = [...writeStringField(1, "t1"), ...writeStringField(5, "SF:44"), ...writeField(6, 0, writeVarint(1))];
  const tu = [...writeLenField(1, trip), ...writeLenField(2, stu(10, "16393", nowSec + 120)), ...writeLenField(3, writeStringField(1, "8751"))];
  return new Uint8Array(writeLenField(2, writeLenField(3, tu)));
}

// In-memory S3 stand-in (rather than the puts-only array the old tests used) so quiet-hour tests
// can seed an existing snapshot and assert whether refreshSnapshot reads/writes it.
function fakeS3(seed: Record<string, string> = {}) {
  const store = new Map<string, string>(Object.entries(seed));
  const puts: { Bucket?: string; Key?: string; Body?: string }[] = [];
  const s3 = {
    send: vi.fn(async (cmd: PutObjectCommand | GetObjectCommand) => {
      if (cmd instanceof PutObjectCommand) {
        const body = cmd.input.Body as string;
        puts.push({ Bucket: cmd.input.Bucket, Key: cmd.input.Key, Body: body });
        store.set(cmd.input.Key as string, body);
        return {};
      }
      if (cmd instanceof GetObjectCommand) {
        const body = store.get(cmd.input.Key as string);
        if (body === undefined) {
          const err = new Error("not found");
          (err as { name: string }).name = "NoSuchKey";
          throw err;
        }
        return { Body: Readable.from([Buffer.from(body)]) };
      }
      throw new Error(`unexpected command: ${cmd}`);
    }),
  } as unknown as S3Client;
  return { s3, puts, store };
}

function fakeSns() {
  const published: PublishCommand[] = [];
  const sns = {
    send: vi.fn(async (cmd: PublishCommand) => { published.push(cmd); return {}; }),
  } as unknown as SNSClient;
  return { sns, published };
}

// Fixed Pacific timestamps (PST, UTC-8) rather than Date.now() so quiet-hour behavior is
// deterministic regardless of when the test suite runs.
const PACIFIC_QUIET_2AM_MS = Date.parse("2026-01-15T10:00:00.000Z"); // 2:00am PST
const PACIFIC_NOON_MS = Date.parse("2026-01-15T20:00:00.000Z"); // 12:00pm PST

describe("refreshSnapshot", () => {
  it("fetches the RG feed, decodes it, and writes a snapshot to S3", async () => {
    const now = Math.floor(Date.now() / 1000);
    const { s3, puts } = fakeS3();
    const fetchImpl = vi.fn(async (url: string) => {
      expect(url).toContain("agency=RG");
      return new Response(feedBytes(now));
    }) as unknown as typeof fetch;

    await refreshSnapshot(s3, "my-bucket", "test-key", Date.now(), fetchImpl);

    expect(puts).toHaveLength(1);
    expect(puts[0].Bucket).toBe("my-bucket");
    expect(puts[0].Key).toBe(SNAPSHOT_KEY);
    const decoded = decodeSnapshot(puts[0].Body as string);
    expect(decoded.index["SF"]["16393"][0].lineRef).toBe("44");
  });

  it("decodes a gzip-compressed upstream response", async () => {
    const now = Math.floor(Date.now() / 1000);
    const { s3, puts } = fakeS3();
    const compressed = new Uint8Array(gzipSync(Buffer.from(feedBytes(now))));
    const fetchImpl = vi.fn(async () => new Response(compressed)) as unknown as typeof fetch;

    await refreshSnapshot(s3, "my-bucket", "test-key", Date.now(), fetchImpl);

    const decoded = decodeSnapshot(puts[0].Body as string);
    expect(decoded.index["SF"]["16393"][0].lineRef).toBe("44");
  });

  it("does not write to S3 when the upstream returns a non-OK status", async () => {
    const { s3, puts } = fakeS3();
    const fetchImpl = vi.fn(async () => new Response("", { status: 503 })) as unknown as typeof fetch;

    await expect(refreshSnapshot(s3, "my-bucket", "test-key", Date.now(), fetchImpl)).resolves.toBeUndefined();
    expect(puts).toHaveLength(0);
  });

  it("does not write to S3 and does not throw when the body is corrupt protobuf", async () => {
    const { s3, puts } = fakeS3();
    const fetchImpl = vi.fn(async () => new Response(new Uint8Array([0x0f]), { status: 200 })) as unknown as typeof fetch;

    await expect(refreshSnapshot(s3, "my-bucket", "test-key", Date.now(), fetchImpl)).resolves.toBeUndefined();
    expect(puts).toHaveLength(0);
  });

  describe("quiet-hours widening (1am-5am Pacific)", () => {
    it("skips the upstream call when the cached snapshot is under 15 minutes old", async () => {
      const fetchedAtMs = PACIFIC_QUIET_2AM_MS - 5 * 60 * 1000; // 5 minutes old
      const { s3, puts } = fakeS3({ [SNAPSHOT_KEY]: encodeSnapshot({}, fetchedAtMs) });
      const fetchImpl = vi.fn(async () => new Response(feedBytes(Math.floor(PACIFIC_QUIET_2AM_MS / 1000)))) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_QUIET_2AM_MS, fetchImpl);

      expect(fetchImpl).not.toHaveBeenCalled();
      expect(puts).toHaveLength(0);
    });

    it("still fetches during quiet hours once the cached snapshot exceeds 15 minutes old", async () => {
      const fetchedAtMs = PACIFIC_QUIET_2AM_MS - 20 * 60 * 1000; // 20 minutes old
      const { s3, puts } = fakeS3({ [SNAPSHOT_KEY]: encodeSnapshot({}, fetchedAtMs) });
      const fetchImpl = vi.fn(async () => new Response(feedBytes(Math.floor(PACIFIC_QUIET_2AM_MS / 1000)))) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_QUIET_2AM_MS, fetchImpl);

      expect(fetchImpl).toHaveBeenCalledTimes(1);
      expect(puts).toHaveLength(1);
    });

    it("fetches during quiet hours when there is no cached snapshot yet", async () => {
      const { s3, puts } = fakeS3();
      const fetchImpl = vi.fn(async () => new Response(feedBytes(Math.floor(PACIFIC_QUIET_2AM_MS / 1000)))) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_QUIET_2AM_MS, fetchImpl);

      expect(fetchImpl).toHaveBeenCalledTimes(1);
      expect(puts).toHaveLength(1);
    });

    it("is not applied outside 1am-5am Pacific, even with a very fresh cached snapshot", async () => {
      const fetchedAtMs = PACIFIC_NOON_MS - 1000; // 1 second old
      const { s3, puts } = fakeS3({ [SNAPSHOT_KEY]: encodeSnapshot({}, fetchedAtMs) });
      const fetchImpl = vi.fn(async () => new Response(feedBytes(Math.floor(PACIFIC_NOON_MS / 1000)))) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS, fetchImpl);

      expect(fetchImpl).toHaveBeenCalledTimes(1);
      expect(puts).toHaveLength(1);
    });
  });

  describe("429-quota SNS alert", () => {
    it("publishes an alert when upstream returns 429 and an SNS client is provided", async () => {
      const { s3 } = fakeS3();
      const { sns, published } = fakeSns();
      const fetchImpl = vi.fn(async () => new Response("", { status: 429 })) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS, fetchImpl, sns, "arn:aws:sns:us-west-2:123:alerts");

      expect(published).toHaveLength(1);
      expect(published[0].input.TopicArn).toBe("arn:aws:sns:us-west-2:123:alerts");
      expect(published[0].input.Subject).toContain("quota exceeded");
    });

    it("does not publish a second alert within the 6-hour cooldown", async () => {
      const { s3 } = fakeS3();
      const { sns, published } = fakeSns();
      const fetchImpl = vi.fn(async () => new Response("", { status: 429 })) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS, fetchImpl, sns, "arn:topic");
      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS + 60_000, fetchImpl, sns, "arn:topic");

      expect(published).toHaveLength(1);
    });

    it("publishes again once the cooldown has elapsed", async () => {
      const { s3 } = fakeS3();
      const { sns, published } = fakeSns();
      const fetchImpl = vi.fn(async () => new Response("", { status: 429 })) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS, fetchImpl, sns, "arn:topic");
      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS + 6 * 60 * 60 * 1000 + 1, fetchImpl, sns, "arn:topic");

      expect(published).toHaveLength(2);
    });

    it("does not throw and does not publish when no SNS client is provided", async () => {
      const { s3 } = fakeS3();
      const fetchImpl = vi.fn(async () => new Response("", { status: 429 })) as unknown as typeof fetch;

      await expect(refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS, fetchImpl)).resolves.toBeUndefined();
    });

    it("does not publish on a non-429 non-OK status", async () => {
      const { s3 } = fakeS3();
      const { sns, published } = fakeSns();
      const fetchImpl = vi.fn(async () => new Response("", { status: 503 })) as unknown as typeof fetch;

      await refreshSnapshot(s3, "my-bucket", "test-key", PACIFIC_NOON_MS, fetchImpl, sns, "arn:topic");

      expect(published).toHaveLength(0);
    });
  });
});
