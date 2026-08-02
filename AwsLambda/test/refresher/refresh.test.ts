import { describe, it, expect, vi } from "vitest";
import { gzipSync } from "node:zlib";
import type { S3Client } from "@aws-sdk/client-s3";
import { refreshSnapshot, SNAPSHOT_KEY } from "../../src/refresher/refresh";
import { decodeSnapshot } from "../../src/gtfsrt/snapshotCodec";
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

function fakeS3() {
  const puts: { Bucket?: string; Key?: string; Body?: string }[] = [];
  const s3 = { send: vi.fn(async (cmd: { input: { Bucket?: string; Key?: string; Body?: string } }) => { puts.push(cmd.input); return {}; }) } as unknown as S3Client;
  return { s3, puts };
}

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
});
