import { GetObjectCommand, PutObjectCommand, type S3Client } from "@aws-sdk/client-s3";
import type { Readable } from "node:stream";

export async function putSnapshotObject(s3: S3Client, bucket: string, key: string, body: string): Promise<void> {
  await s3.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: "application/json" }));
}

export async function getSnapshotObject(s3: S3Client, bucket: string, key: string): Promise<string | null> {
  try {
    const res = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const stream = res.Body as Readable;
    const chunks: Buffer[] = [];
    for await (const chunk of stream) chunks.push(chunk as Buffer);
    return Buffer.concat(chunks).toString("utf-8");
  } catch (err) {
    if (err instanceof Error && err.name === "NoSuchKey") return null;
    throw err;
  }
}
