import { S3Client } from "@aws-sdk/client-s3";
import { createReader } from "./render";

const s3 = new S3Client({});
const bucket = process.env.SNAPSHOT_BUCKET;
const internalKey = process.env.INTERNAL_SHARED_KEY;
if (!bucket || !internalKey) {
  throw new Error("SNAPSHOT_BUCKET and INTERNAL_SHARED_KEY must be set");
}

export const handler = createReader(s3, bucket, internalKey);
