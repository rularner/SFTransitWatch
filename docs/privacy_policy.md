---
layout: default
title: Privacy Policy
---

# Privacy Policy

**Effective date:** August 4, 2026
**Last updated:** August 4, 2026

This Privacy Policy describes how the SF Transit Watch app ("the App", "we",
"our") handles information when you use the iPhone and Apple Watch app. SF
Transit Watch is an independent project that displays real-time arrival
information for San Francisco Bay Area public transit using the 511.org
Transit API. The App offers an optional paid subscription, described in
Section 5.

## Who we are

SF Transit Watch is published by Rusty Larner. You can reach us at
**sftransitwatch@larner.org** for any privacy questions or requests.

## Summary

- We do **not** sell your data.
- We do **not** show ads, and we do **not** use any advertising or
  third-party analytics SDKs.
- We do **not** require an account, sign-in, email address, or any other
  personal identifier to use the App.
- The App offers two data-source modes, and **which one you choose is the
  main thing that determines what we receive**:
  - **Direct 511.org** — you supply your own API key, requests go straight
    from your device to 511.org, and no server of ours is involved at any
    point. In this mode we receive nothing whatsoever, including no
    diagnostics.
  - **Remote server** — an optional paid subscription that routes requests
    through our Cloudflare-hosted proxy. In this mode the proxy necessarily
    receives your location and the stops you look up, because that is what
    it forwards to 511.org on your behalf.
- If you use the remote server, the App sends your install ID, platform, app
  version, and bundle identifier to obtain an access credential, and sends
  an App Store transaction identifier so the server can confirm your
  subscription is active (Section 5).
- We do not store your location. Our proxy's request logs, which include
  your IP address and the paths you request, are kept briefly for abuse
  prevention and debugging and then deleted (see Data retention).
- Your favorites, pinned stops, commute stops, and any 511.org API key are
  stored only on your device.

## Information we handle

### 1. Location

When you grant the App "While Using the App" location permission, the App
reads your current GPS coordinates from the operating system and sends
them, in a single API request, to the 511.org Transit API in order to look
up bus and rail stops near you.

- Location is used in real time and is **not stored** on our servers.
- Location is **not** included in any telemetry or diagnostic data we
  collect (see Section 4).
- You can revoke location permission at any time in **Settings > Privacy &
  Security > Location Services** on iPhone, or **Settings > Privacy &
  Security > Location Services** on Apple Watch. The App will continue to
  work for stops you have already saved, but it will not be able to
  discover new nearby stops.

### 2. Data source configuration

The App supports two modes for fetching transit data. You choose at first
launch and can change it in Settings.

**Direct 511.org (API key mode)**

You enter a free API key from [511.org](https://511.org/developers/).

- The key is stored locally on your device (`UserDefaults` / `@AppStorage`).
- If you use both the iPhone and Apple Watch app, the key may be transferred
  between the two over Apple's encrypted Watch Connectivity channel.
- The key is sent only to 511.org as part of normal API requests. It is not
  transmitted anywhere else and is not included in telemetry.
- You can clear the key at any time from the in-app Settings screen.

**Remote server (self-provision mode, optional, paid)**

On first launch, if no API key is set, the App offers to connect to our
optional Cloudflare-hosted proxy server, which requires a subscription
(Section 5). If you subscribe and connect:

- The App sends your **install ID** (a random UUID), **platform**
  (`ios` or `watchos`), **app version**, **bundle identifier**, and the
  **original transaction identifier** of your App Store subscription to our
  server, in order to obtain an access credential. This exchange uses an
  asymmetric cryptographic signature embedded in the app binary to prove the
  request comes from a genuine install of this app.
- The server issues an opaque access token stored only on your device. The
  token is used on every subsequent request to authenticate with the proxy.
  Its lifetime is tied to your subscription period, so the App repeats this
  exchange periodically while your subscription is active.
- **What the proxy sees during normal use.** Every request the App makes
  through the proxy carries your device's IP address, your access token, and
  the request itself — which means your latitude and longitude when looking
  up nearby stops, and the stop identifier when looking up arrivals. The
  proxy cannot fetch transit data for you without this. It records a log
  line per request containing the request path, a label derived from your
  install ID, and your IP address as part of ordinary HTTP serving. We do
  not store your coordinates.
- If you prefer not to subscribe, tap "Use 511.org key instead" to enter an
  API key directly, or tap Cancel. If you cancel without entering a key,
  the App will show a message on the home screen until you configure one
  of the two options.

### 3. Favorites, pinned stops, and commute stops

Stops you mark as favorites, pin to the home screen, or assign as your
morning/afternoon commute stop are stored locally on your device:

- in `UserDefaults`, and
- in a shared App Group container so the watch face complication can read
  them without a network call.

These records contain only the stop's identifier and basic metadata (name,
agency, location coordinates of the stop itself). They are **not**
uploaded to our servers. Deleting the App removes them from your device.

### 4. Diagnostic telemetry (anonymous)

When you are using the remote server, the App sends a small amount of
anonymous diagnostic data so we can tell whether requests to 511.org are
succeeding.

This telemetry is sent **only in remote-server mode**, and it is a strict
subset of what the proxy already receives in order to serve your requests at
all: it adds timing and success/failure information, and contains nothing
about you that Section 2 does not already describe. In direct 511.org mode
no telemetry is sent, because there is no server of ours involved. **If you
do not want to send diagnostics, use direct 511.org mode** — see "Your
rights and choices" below.

Each event contains only:

- a randomly generated **install ID** (a UUID created on first launch and
  stored on your device — it is not linked to your Apple ID, email, name,
  device ID, or advertising ID);
- the platform (`watch` or `ios`), app version, and build number;
- the API endpoint that was called (e.g. `StopMonitoring`,
  `StopPlace`), its HTTP status, request latency in milliseconds, and a
  coarse error category (e.g. `network`, `http_5xx`, `parse`);
- a cache-status hint from our proxy, when present;
- a timestamp.

Telemetry events explicitly **do not** include your location, the stop
you looked up, your 511.org API key, your IP address as a stored field,
or any other personal information. They are used only to monitor app
health and reliability.

You can also contact us at the address above and we will delete all events
associated with your install ID.

### 5. Subscription and purchases

The remote server described in Section 2 requires an auto-renewing
subscription purchased through the App Store.

- **We never see your payment details.** The purchase is handled entirely by
  Apple. We do not receive your name, email address, billing address, or any
  card or payment information, and we have no ability to charge you
  directly.
- **What we do receive** is the **original transaction identifier** Apple
  assigns to your subscription. The App sends it to our server, which passes
  it to Apple's App Store Server API to ask a single question: is this
  subscription currently active, and when does it expire? Apple's answer
  determines how long your access credential remains valid.
- This identifier is stored alongside your access credential for the
  lifetime of that credential, so that we can re-check the subscription as
  it renews. It is not linked by us to your identity, and we have no way to
  resolve it to an Apple Account.
- Managing, cancelling, or requesting a refund for the subscription is done
  through Apple, in **Settings → Apple Account → Subscriptions** on iPhone,
  and is governed by Apple's terms and privacy policy.

### 6. Siri and Shortcuts

If you set up Siri voice commands or Shortcuts for the App:

- Phrases you record are processed by Apple's Siri service under
  [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).
- The App "donates" intents (e.g. "find nearby stops", "check the 38
  bus") to the system so Siri can suggest them. These donations stay on
  your device and are governed by Apple.
- We do not receive transcripts or audio.

### 7. System logs

The App writes routine diagnostic messages to the standard Apple
unified logging system (`os.Logger`). These logs live on your device,
follow Apple's privacy redaction rules, and are only shared with us if
you choose to send a sysdiagnose or crash report through Apple. We do
not collect them automatically.

## Third parties we send data to

| Recipient | What is sent | Why |
|-----------|--------------|-----|
| **511.org Transit API** (operated by the Metropolitan Transportation Commission) | Your latitude/longitude when looking up nearby stops, the stop code when looking up arrivals, and your 511.org API key. | To fetch transit data. Governed by the [511.org terms of use](https://511.org/about/terms-of-use). |
| **Cloudflare (optional proxy)** | On connection: install ID, platform, app version, bundle identifier, and your App Store original transaction identifier (to obtain an access token). During normal use: the same location and stop-code requests as 511.org above, plus your device's IP address as part of normal HTTP transit and an app token header. | Credential issuance and subscription verification; then to reduce load on 511.org and add caching. The proxy does not log request bodies or your API key beyond what is required to forward the request. If you do not use the proxy, no data is ever sent here. |
| **Apple (App Store Server API)** | Your subscription's original transaction identifier, sent by our server to Apple. | To confirm your subscription is active and when it expires, which determines how long your access credential is valid. Only applies if you subscribe. |
| **Apple (platform services)** | Location permission, Siri intents, Watch Connectivity messages, push of complication updates, and the subscription purchase itself. | Standard Apple platform services, governed by Apple's Privacy Policy. |

We do not share, sell, rent, or trade any information with advertisers or
data brokers.

## Data retention

- **On your device:** favorites, pinned stops, commute stops, and your
  511.org API key remain on your device until you delete them in the App
  or uninstall the App.
- **Telemetry (if applicable):** retained for up to **90 days** and then
  deleted or aggregated.
- **Server-side request logs at our proxy / telemetry endpoint:** retained
  for up to **30 days** for abuse prevention and debugging, then deleted.
- **511.org and Apple** retain data per their own policies, linked above.

## Your rights and choices

Because we do not collect data tied to your identity, we generally cannot
look up records about a specific person. You can still:

- **Stop sending us anything at all**, by using direct 511.org mode. Enter
  your own API key in the in-app Settings screen and tap **Clear** under
  **Worker proxy** to remove the server credential. Entering a key alone is
  not sufficient — the App keeps using the proxy while it still holds a
  credential for it. Once cleared, the App communicates only with 511.org,
  and no location, request, or diagnostic data reaches us. (This does not
  cancel your subscription; cancel that through Apple.)
- **Revoke location access** at any time in iOS / watchOS Settings.
- **Clear your API key, favorites, pinned stops, and commute stops** from
  the in-app Settings screen.
- **Reset your install ID** by deleting and reinstalling the App. The
  previous ID is no longer associated with your device.
- **Request deletion of telemetry tied to your install ID** by emailing
  us with the install ID (visible by tapping the build number in
  Settings).

If you are a California resident, the California Consumer Privacy Act
(CCPA) gives you the right to know, delete, correct, and not be
discriminated against for exercising these rights. If you are in the
European Economic Area or the United Kingdom, the GDPR / UK GDPR give
you similar rights, plus the right to object and the right to data
portability. Contact us at the email above to exercise any of these
rights.

## Children's privacy

The App is a general-audience utility and is not directed to children
under 13. We do not knowingly collect personal information from
children. If you believe a child has provided us with information,
please contact us and we will delete it.

## Security

- All network requests use HTTPS.
- Watch ↔ iPhone synchronization uses Apple's encrypted Watch
  Connectivity transport.
- Your 511.org API key never leaves your device except to be sent to
  511.org itself, in direct mode. It is never sent to our proxy — in
  remote-server mode the proxy uses its own 511.org credentials, and the
  App omits the key from the request entirely.
- No system can be guaranteed 100% secure, but we follow standard Apple
  platform security practices.

## Changes to this policy

We may update this policy from time to time. Material changes will be
reflected by updating the "Effective date" above. Continued use of the
App after a change constitutes acceptance of the updated policy.

## Contact

Questions, requests, or complaints about this Privacy Policy:

**Email:** sftransitwatch@larner.org
**Repository:** <https://github.com/rularner/SFTransitWatch>
