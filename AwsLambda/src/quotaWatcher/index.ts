import { LambdaClient } from "@aws-sdk/client-lambda";
import { SNSClient } from "@aws-sdk/client-sns";
import { checkQuota } from "./checkQuota";

const lambdaClient = new LambdaClient({});
const snsClient = new SNSClient({});

export const handler = async (): Promise<void> => {
  const topicArn = process.env.ALERT_TOPIC_ARN;
  if (!topicArn) {
    throw new Error("ALERT_TOPIC_ARN must be set");
  }
  await checkQuota(lambdaClient, snsClient, topicArn);
};
