import { describe, it, expect, vi } from "vitest";
import { Readable } from "node:stream";
import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
import type { S3Client } from "@aws-sdk/client-s3";
import { createReader } from "../../src/reader/render";
import { encodeSnapshot } from "../../src/gtfsrt/snapshotCodec";
import type { ArrivalsIndex } from "../../src/gtfsrt/indexBuilder";

const INDEX: ArrivalsIndex = {
  SF: { "16393": [{ lineRef: "44", directionRef: "IB", vehicleRef: "8751", expectedArrival: 200, onward: [{ stopId: "16301", time: 300 }] }] },
};

function fakeS3(body: string | null) {
  const send = vi.fn(async () => {
    if (body === null) {
      const err = new Error("nope");
      (err as { name: string }).name = "NoSuchKey";
      throw err;
    }
    return { Body: Readable.from([Buffer.from(body)]) };
  });
  return { send } as unknown as S3Client;
}

function event(qs: string, key = "secret"): APIGatewayProxyEventV2 {
  return { rawQueryString: qs, headers: { "x-internal-key": key } } as unknown as APIGatewayProxyEventV2;
}

describe("createReader", () => {
  it("rejects a request missing the correct internal key", async () => {
    const s3 = fakeS3(encodeSnapshot(INDEX, Date.now()));
    const reader = createReader(s3, "bucket", "secret");

    // Cast: APIGatewayProxyResultV2 = APIGatewayProxyStructuredResultV2 | string (a Lambda may
    // return a bare string body). render.ts always returns the structured form; this narrows the
    // type so the test can read .statusCode/.body without touching createReader's public signature.
    const res = (await reader(event("agency=SF&stopCode=16393", "wrong"))) as APIGatewayProxyStructuredResultV2;

    expect(res.statusCode).toBe(401);
  });

  it("slices the index by agency and stopCode, capping onward calls", async () => {
    const s3 = fakeS3(encodeSnapshot(INDEX, Date.now()));
    const reader = createReader(s3, "bucket", "secret");

    const res = (await reader(event("agency=SF&stopCode=16393&MaximumNumberOfCallsOnwards=1"))) as APIGatewayProxyStructuredResultV2;

    expect(res.statusCode).toBe(200);
    const body = JSON.parse(res.body as string);
    const mvj = body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit[0].MonitoredVehicleJourney;
    expect(mvj.LineRef).toBe("44");
    expect(mvj.OnwardCalls.OnwardCall).toHaveLength(1);
  });

  it("returns an empty visit list for an unknown stop", async () => {
    const s3 = fakeS3(encodeSnapshot(INDEX, Date.now()));
    const reader = createReader(s3, "bucket", "secret");

    const res = (await reader(event("agency=SF&stopCode=99999"))) as APIGatewayProxyStructuredResultV2;

    const body = JSON.parse(res.body as string);
    expect(body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit).toEqual([]);
  });

  it("returns an empty visit list when no snapshot has ever been written", async () => {
    const s3 = fakeS3(null);
    const reader = createReader(s3, "bucket", "secret");

    const res = (await reader(event("agency=SF&stopCode=16393"))) as APIGatewayProxyStructuredResultV2;

    const body = JSON.parse(res.body as string);
    expect(body.ServiceDelivery.StopMonitoringDelivery.MonitoredStopVisit).toEqual([]);
  });

  it("re-fetches from S3 only after the 30s local-cache window elapses", async () => {
    const s3 = fakeS3(encodeSnapshot(INDEX, Date.now()));
    let now = 1_000_000;
    const reader = createReader(s3, "bucket", "secret", () => now);

    await reader(event("agency=SF&stopCode=16393"));
    expect(s3.send).toHaveBeenCalledTimes(1);

    now += 10_000; // still within the 30s window
    await reader(event("agency=SF&stopCode=16393"));
    expect(s3.send).toHaveBeenCalledTimes(1);

    now += 25_000; // now 35s past the first load — past the window
    await reader(event("agency=SF&stopCode=16393"));
    expect(s3.send).toHaveBeenCalledTimes(2);
  });
});
