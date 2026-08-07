import { S3Client } from "@aws-sdk/client-s3";
import { SNSClient } from "@aws-sdk/client-sns";
import { refreshSnapshot } from "./refresh";

const s3 = new S3Client({});
const sns = new SNSClient({});

export const handler = async (): Promise<void> => {
  const bucket = process.env.SNAPSHOT_BUCKET;
  const api511Key = process.env.API_511_KEY;
  const alertTopicArn = process.env.ALERT_TOPIC_ARN;
  if (!bucket || !api511Key || !alertTopicArn) {
    throw new Error("SNAPSHOT_BUCKET, API_511_KEY, and ALERT_TOPIC_ARN must be set");
  }
  await refreshSnapshot(s3, bucket, api511Key, Date.now(), fetch, sns, alertTopicArn);
};
