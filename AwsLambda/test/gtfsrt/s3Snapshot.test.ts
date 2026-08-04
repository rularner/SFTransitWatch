import { describe, it, expect, vi } from "vitest";
import { Readable } from "node:stream";
import type { S3Client } from "@aws-sdk/client-s3";
import { PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { putSnapshotObject, getSnapshotObject } from "../../src/gtfsrt/s3Snapshot";

function fakeS3(handler: (cmd: unknown) => unknown): S3Client {
  return { send: vi.fn(async (cmd: unknown) => handler(cmd)) } as unknown as S3Client;
}

describe("putSnapshotObject", () => {
  it("sends a PutObjectCommand with the bucket, key, and body", async () => {
    const calls: PutObjectCommand[] = [];
    const s3 = fakeS3((cmd) => { calls.push(cmd as PutObjectCommand); return {}; });

    await putSnapshotObject(s3, "my-bucket", "snapshots/RG.json", '{"a":1}');

    expect(calls).toHaveLength(1);
    expect(calls[0]).toBeInstanceOf(PutObjectCommand);
    expect(calls[0].input).toEqual({
      Bucket: "my-bucket", Key: "snapshots/RG.json", Body: '{"a":1}', ContentType: "application/json",
    });
  });
});

describe("getSnapshotObject", () => {
  it("returns the object body as a string", async () => {
    const s3 = fakeS3((cmd) => {
      expect(cmd).toBeInstanceOf(GetObjectCommand);
      expect((cmd as GetObjectCommand).input).toEqual({ Bucket: "my-bucket", Key: "snapshots/RG.json" });
      return { Body: Readable.from([Buffer.from('{"a":1}')]) };
    });

    expect(await getSnapshotObject(s3, "my-bucket", "snapshots/RG.json")).toBe('{"a":1}');
  });

  it("returns null when the object does not exist (NoSuchKey)", async () => {
    const s3 = fakeS3(() => {
      const err = new Error("not found");
      (err as { name: string }).name = "NoSuchKey";
      throw err;
    });

    expect(await getSnapshotObject(s3, "my-bucket", "snapshots/RG.json")).toBeNull();
  });

  it("rethrows unexpected S3 errors", async () => {
    const s3 = fakeS3(() => { throw new Error("access denied"); });

    await expect(getSnapshotObject(s3, "my-bucket", "snapshots/RG.json")).rejects.toThrow("access denied");
  });
});
