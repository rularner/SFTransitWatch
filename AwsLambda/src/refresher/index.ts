import { S3Client } from "@aws-sdk/client-s3";
import { refreshSnapshot } from "./refresh";

const s3 = new S3Client({});

export const handler = async (): Promise<void> => {
  const bucket = process.env.SNAPSHOT_BUCKET;
  const api511Key = process.env.API_511_KEY;
  if (!bucket || !api511Key) {
    throw new Error("SNAPSHOT_BUCKET and API_511_KEY must be set");
  }
  await refreshSnapshot(s3, bucket, api511Key, Date.now());
};
