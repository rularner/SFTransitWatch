import type { LambdaClient } from "@aws-sdk/client-lambda";
import { GetAccountSettingsCommand } from "@aws-sdk/client-lambda";
import type { SNSClient } from "@aws-sdk/client-sns";
import { PublishCommand } from "@aws-sdk/client-sns";

// The account-wide Lambda concurrent-execution limit observed when this project was first
// deployed (2026-08) — new/unverified AWS accounts are commonly throttled to this value as an
// anti-fraud measure, well below the standard default of 1000. ReservedConcurrentExecutions on
// RefresherFunction/ReaderFunction in template.yaml was dropped because AWS requires at least 10
// units of *unreserved* concurrency to remain account-wide, and any nonzero reservation at this
// baseline violates that floor. This watcher exists to catch the moment AWS raises it, so the
// reservations — the actual cost/blast-radius guardrail — can be restored. See the TODO.md entry
// and the loud comment in template.yaml.
export const KNOWN_THROTTLED_LIMIT = 10;

// Called on a daily schedule (see template.yaml). Never throws on a missing/malformed API
// response — logs and returns, matching this project's degrade-gracefully convention for
// background jobs; a monitoring utility failing loudly would itself become an operational
// problem, not a fix for one.
export async function checkQuota(lambdaClient: LambdaClient, snsClient: SNSClient, topicArn: string): Promise<void> {
  const settings = await lambdaClient.send(new GetAccountSettingsCommand({}));
  const currentLimit = settings.AccountLimit?.ConcurrentExecutions;
  if (currentLimit === undefined) {
    console.error("GetAccountSettings did not return AccountLimit.ConcurrentExecutions");
    return;
  }

  if (currentLimit <= KNOWN_THROTTLED_LIMIT) {
    console.log(`Lambda concurrency limit still at ${currentLimit}, no change from the known throttled baseline.`);
    return;
  }

  const availableForReservation = currentLimit - 10;
  await snsClient.send(new PublishCommand({
    TopicArn: topicArn,
    Subject: "SFTransitWatch: AWS Lambda concurrency limit has increased",
    Message:
      `Your account's Lambda concurrent-execution limit is now ${currentLimit} ` +
      `(was throttled at ${KNOWN_THROTTLED_LIMIT}). Restore ReservedConcurrentExecutions on ` +
      `RefresherFunction (1) and ReaderFunction (5) in AwsLambda/template.yaml — see the comment ` +
      `there and the TODO.md entry for context. AWS requires at least 10 units of unreserved ` +
      `concurrency account-wide, so a limit of ${currentLimit} currently allows up to ` +
      `${availableForReservation} units of total reservation across all functions.`,
  }));
}
