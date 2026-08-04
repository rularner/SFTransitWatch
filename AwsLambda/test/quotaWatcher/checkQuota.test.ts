import { describe, it, expect, vi } from "vitest";
import type { LambdaClient } from "@aws-sdk/client-lambda";
import { GetAccountSettingsCommand } from "@aws-sdk/client-lambda";
import type { SNSClient } from "@aws-sdk/client-sns";
import { PublishCommand } from "@aws-sdk/client-sns";
import { checkQuota, KNOWN_THROTTLED_LIMIT } from "../../src/quotaWatcher/checkQuota";

function fakeLambdaClient(concurrentExecutions: number | undefined): LambdaClient {
  return {
    send: vi.fn(async (cmd: unknown) => {
      expect(cmd).toBeInstanceOf(GetAccountSettingsCommand);
      return concurrentExecutions === undefined
        ? {}
        : { AccountLimit: { ConcurrentExecutions: concurrentExecutions } };
    }),
  } as unknown as LambdaClient;
}

function fakeSnsClient() {
  const published: PublishCommand[] = [];
  const client = { send: vi.fn(async (cmd: unknown) => { published.push(cmd as PublishCommand); return {}; }) } as unknown as SNSClient;
  return { client, published };
}

describe("checkQuota", () => {
  it("does not publish when the limit is still at the known throttled baseline", async () => {
    const lambdaClient = fakeLambdaClient(KNOWN_THROTTLED_LIMIT);
    const { client: snsClient, published } = fakeSnsClient();

    await checkQuota(lambdaClient, snsClient, "arn:aws:sns:us-west-2:123456789012:test-topic");

    expect(published).toHaveLength(0);
  });

  it("does not publish when the limit is below the known throttled baseline", async () => {
    const lambdaClient = fakeLambdaClient(5);
    const { client: snsClient, published } = fakeSnsClient();

    await checkQuota(lambdaClient, snsClient, "arn:aws:sns:us-west-2:123456789012:test-topic");

    expect(published).toHaveLength(0);
  });

  it("publishes an alert with the current limit and available-reservation math when the limit has risen", async () => {
    const lambdaClient = fakeLambdaClient(100);
    const { client: snsClient, published } = fakeSnsClient();

    await checkQuota(lambdaClient, snsClient, "arn:aws:sns:us-west-2:123456789012:test-topic");

    expect(published).toHaveLength(1);
    expect(published[0].input.TopicArn).toBe("arn:aws:sns:us-west-2:123456789012:test-topic");
    expect(published[0].input.Message).toContain("now 100");
    expect(published[0].input.Message).toContain("was throttled at 10");
    expect(published[0].input.Message).toContain("up to 90 units");
  });

  it("logs and does not throw or publish when AccountLimit.ConcurrentExecutions is missing", async () => {
    const lambdaClient = fakeLambdaClient(undefined);
    const { client: snsClient, published } = fakeSnsClient();
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    await expect(checkQuota(lambdaClient, snsClient, "arn:aws:sns:us-west-2:123456789012:test-topic")).resolves.toBeUndefined();

    expect(published).toHaveLength(0);
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });
});
