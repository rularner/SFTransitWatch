# Security Policy

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**

Report privately using either:

- **GitHub private vulnerability reporting** — the "Report a vulnerability"
  button under this repository's [Security tab](https://github.com/rularner/SFTransitWatch/security/advisories/new).
  This is the preferred route.
- **Email** — <sftransitwatch@larner.org>. Please put "SECURITY" in the
  subject line.

This is a small independent project maintained by one person in their spare
time. Expect an acknowledgement within **7 days** and an assessment within
**30 days**. If a report is confirmed, you will be credited in the fix unless
you would rather not be.

Please include whatever you have: what you did, what happened, what you
expected, and the app version or worker/Lambda endpoint involved. A proof of
concept helps a great deal.

Please give a reasonable window to ship a fix before disclosing publicly.
App fixes have to go through App Store review, which is outside our control
and typically adds a few days.

## Supported versions

Only the **current App Store release** and the **currently deployed** worker
and Lambda are supported. There are no backported fixes to older builds; the
fix ships in the next release.

## Scope

This repository contains three deployable pieces, all in scope:

| Component | Path | Notes |
|---|---|---|
| iOS + watchOS app | `SFTransitWatch/`, `SFTransitWatch Watch App/`, `SFTransitWatchPackage/` | Swift |
| Cloudflare Worker proxy | `CloudflareWorker/` | Serves `api.sftransitwatch.com` |
| AWS Lambda GTFS-RT service | `AwsLambda/` | Feed refresher + reader behind the worker |

Particularly interested in: authentication bypass on the worker's token
gate, anything that lets one client read another client's data, subscription
verification bypass, injection into the upstream 511.org or App Store Server
API requests, and secret disclosure.

**Out of scope:**

- Reports against **511.org** itself. Their API is upstream of us — report
  those to 511.org directly.
- Denial of service by simply sending a lot of traffic. The rate limits are
  known and deliberately modest.
- Missing hardening headers or TLS configuration nits on the static GitHub
  Pages docs site, which serves no user data.
- Anything requiring a jailbroken device, a modified app binary, or physical
  access to an unlocked device.

## Known design limitations

These are understood tradeoffs, not undiscovered bugs. Reports about them
are still welcome if you can show impact beyond what is described here.

- **The self-provision signing key ships inside the app.** `Info.plist`
  carries `SELF_PROVISION_PRIVATE_KEY`, the EC P-256 key used to sign
  `/self-provision` requests. Anyone can extract it from a downloaded build.
  It proves "a genuine build of this app made this request," not "this
  particular user is legitimate" — access still additionally requires an
  App Store transaction ID for an active subscription, verified server-side
  against Apple. Attestation would be the stronger primitive.
- **Access tokens outlive subscription changes.** A credential's lifetime is
  the subscription's expiry plus a short grace period, and nothing shortens
  it early. A refund or mid-period cancellation leaves a working token until
  it expires on its own. There is no App Store Server Notifications endpoint
  yet.
- **Subscription verification falls back to Apple's sandbox** when
  production returns 401/404, which is required for TestFlight builds to
  work at all and is a permanent part of the design.

## Handling of secrets

No secret should ever be committed. `Developer.xcconfig` (which holds the
signing key and team ID) is gitignored; worker secrets live in Wrangler
secrets and Lambda secrets in the SAM stack.

If you believe a credential has been committed, please report it privately
using the process above rather than opening an issue — including if you find
one in the git history rather than at `HEAD`.
