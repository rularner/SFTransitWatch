# Cloudflare Worker Setup

This Worker proxies and caches 511.org requests for the iPhone and Apple Watch apps.

## Required Cloudflare Git Build Settings

When using Cloudflare's Git integration, set:

- **Build command**: `cd CloudflareWorker && npm run deploy`
- **Environment variables**:
  - `TRANSIT_CACHE_KV_ID=<your_transit_cache_namespace_id>`
  - `CLIENT_TOKENS_KV_ID=<your_client_tokens_namespace_id>`

The deploy script generates `.wrangler.generated.jsonc` from `wrangler.jsonc`,
substituting both `__TRANSIT_CACHE_KV_ID__` and `__CLIENT_TOKENS_KV_ID__`
before running Wrangler deploy.

## GTFS-RT Lambda dependency (read before merging AwsLambda changes)

`/StopMonitoring` proxies to an AWS Lambda reader (see `AwsLambda/`) and depends on two
Worker secrets:

- `GTFSRT_READER_URL` — the reader Lambda's Function URL.
- `GTFSRT_INTERNAL_KEY` — the shared secret the Worker sends as `X-Internal-Key`.

Both require the `AwsLambda/` SAM stack to already be deployed before they can be set (the
Function URL isn't known until the stack exists). Because `.github/workflows/deploy-lambda.yml`
auto-deploys on push to `main` for `AwsLambda/**` changes, and Cloudflare's own Git integration
auto-deploys the Worker on *any* push to `main`, merging both sides in one shot risks the Worker
going live before the secrets are set.

**Recommended rollout order:**

1. Merge `AwsLambda/**` changes to `main` first and let `deploy-lambda.yml` provision/update the
   SAM stack.
2. Verify the reader Function URL directly (e.g. `curl` it with the internal key) once the stack
   is deployed.
3. Set the two Worker secrets with `wrangler secret put GTFSRT_READER_URL` and
   `wrangler secret put GTFSRT_INTERNAL_KEY` (value must match the stack's `InternalSharedKey`
   parameter).
4. Only then merge/deploy the Worker proxy change.

If the Worker proxy code is deployed before the secrets are set, `/StopMonitoring` degrades to
returning an empty `MonitoredStopVisit[]` (HTTP 200, no error) rather than failing — so it's a
silent-but-safe transitional state, not an outage in the sense of errors, but it does mean no
live arrivals data until the secrets are set.

## Local Development

Use the same variables locally:

- `cd CloudflareWorker`
- `TRANSIT_CACHE_KV_ID=<id> CLIENT_TOKENS_KV_ID=<id> npm run dev`

Type generation also needs both:

- `TRANSIT_CACHE_KV_ID=<id> CLIENT_TOKENS_KV_ID=<id> npm run cf-typegen`

## Self-provision (automatic token issuance)

The worker exposes a `POST /self-provision` endpoint that the app calls on
first launch to obtain a token automatically. No operator action is required
per device. The app signs a short-lived ES256 JWT with a private key baked
into the app binary at build time; the worker verifies the signature using a
corresponding public key stored as a Cloudflare Worker secret.

**One-time operator setup:**

1. Generate the key pair:
   ```bash
   openssl ecparam -name prime256v1 -genkey -noout -out /tmp/provision.pem
   # Private key → Developer.xcconfig (local) and Xcode Cloud secret
   openssl ec -in /tmp/provision.pem -outform DER | base64 | tr -d '\n'
   # Public key → SELF_PROVISION_PUBLIC_KEY worker secret
   openssl ec -in /tmp/provision.pem -pubout -outform DER | base64 | tr -d '\n'
   rm /tmp/provision.pem
   ```
2. Set the worker secret:
   ```bash
   npx wrangler secret put SELF_PROVISION_PUBLIC_KEY
   # Paste the Base64 SPKI public key when prompted
   ```
3. Set `SELF_PROVISION_PRIVATE_KEY` in `Developer.xcconfig` (local builds)
   and as an Xcode Cloud environment variable (CI builds).

Self-provisioned tokens are stored in `CLIENT_TOKENS` with a label of the
form `self-prov:<platform>:<first8-of-install-id>:<app-version>`, which is
visible in Cloudflare worker logs for abuse detection.

## Issuing client tokens (manual, for specific devices)

For devices you want to provision without the first-launch prompt — e.g.,
family members you want to add directly — you can mint a bootstrap link:

```bash
WORKER_URL=https://your-worker.workers.dev ./scripts/issue-token.sh <label>
```

The printed bootstrap link goes to the device via Messages/Mail.
- **iOS**: paste it into Settings → Worker proxy.
- **watchOS**: tap the link in the message — the watch app accepts it via
  the `/wt` universal link handler.

Revoke any token (self-provisioned or manually issued) by deleting its hash
from KV:
```bash
npx wrangler kv key delete --binding CLIENT_TOKENS <hash>
```

## Apple communication health check

After every deploy, `npm run postdeploy` calls `GET /healthz/appstore` on
the worker that was just deployed. This verifies:

- `SELF_PROVISION_PUBLIC_KEY` is configured and is a valid P-256 SPKI key.
- The `APPSTORE_KEY_ID`/`APPSTORE_ISSUER_ID`/`APPSTORE_PRIVATE_KEY`/`APPSTORE_BUNDLE_ID`
  secrets can successfully authenticate to Apple's App Store Server API.

If either check fails, the script exits non-zero and the Cloudflare Workers
Build shows as failed — even though the new code is already live. Treat a
red build here as "Apple credentials need attention", not "the deploy
didn't go out".

**One-time operator setup:**

1. Set the health check bearer token as a worker secret:
   ```bash
   npx wrangler secret put HEALTHCHECK_TOKEN
   ```
2. In the Cloudflare Workers Build project settings, add these build
   environment variables:
   - `HEALTHCHECK_TOKEN` — same value as the worker secret above.
   - `WORKERS_DEV_URL` — this worker's `*.workers.dev` hostname (e.g.
     `sftransitwatch.rusty-cloudflare.workers.dev`), used to check PR
     builds since `WORKER_HOSTNAME` isn't repointed for those.

**Note:** `/healthz/appstore` makes a real call to Apple's App Store
Server API on every invocation. It's meant for the `postdeploy` step and
manual operator checks — don't point uptime-monitoring/polling services at
it.

## Notes

- `TRANSIT_CACHE_KV_ID` and `CLIENT_TOKENS_KV_ID` are required for `npm run deploy`, `npm run dev`, and `npm run cf-typegen`.
- `SELF_PROVISION_PUBLIC_KEY` is required for the `/self-provision` endpoint to work. Without it, all self-provision attempts will fail with 401.
- `.wrangler.generated.jsonc` is generated at runtime and is gitignored.
- `HEALTHCHECK_TOKEN` and `WORKERS_DEV_URL` are required for `npm run postdeploy` to work, in addition to the `WORKER_HOSTNAME` already required by `npm run deploy`. See "Apple communication health check" above.
- `GTFSRT_READER_URL` and `GTFSRT_INTERNAL_KEY` are required for `/StopMonitoring` to return live data. `GTFSRT_READER_URL` is the AWS Lambda reader's Function URL (the `AwsLambda` SAM stack's `ReaderFunctionUrl` output); `GTFSRT_INTERNAL_KEY` is the shared secret the Worker sends as `X-Internal-Key` and must match the SAM stack's `InternalSharedKey` parameter. Both are set via `wrangler secret put`. See "GTFS-RT Lambda dependency" above for rollout ordering. Without them, `/StopMonitoring` degrades to an empty `MonitoredStopVisit[]` rather than erroring.
