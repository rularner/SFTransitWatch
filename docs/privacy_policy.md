---
layout: default
title: Privacy Policy
---

# Privacy Policy

**Effective date:** May 6, 2026
**Last updated:** May 6, 2026

This Privacy Policy describes how the SF Transit Watch app ("the App", "we",
"our") handles information when you use the iPhone and Apple Watch app. SF
Transit Watch is an independent, non-commercial project that displays
real-time arrival information for San Francisco Bay Area public transit
using the 511.org Transit API.

## Who we are

SF Transit Watch is published by Rusty Larner. You can reach us at
**rlarner@gmail.com** for any privacy questions or requests.

## Summary

- We do **not** sell your data.
- We do **not** show ads, and we do **not** use any advertising or
  third-party analytics SDKs.
- We do **not** require an account, sign-in, email address, or any other
  personal identifier to use the App.
- Your location is used on-device to look up nearby stops and is sent only
  to the 511.org Transit API (or our optional Cloudflare-hosted proxy in
  front of it). It is not stored by us.
- Your favorites, pinned stops, commute stops, and 511.org API key are
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

### 2. Your 511.org API key

To fetch transit data, the App uses an API key issued to you by
[511.org](https://511.org/developers/). You enter this key yourself in
Settings (or load it via a one-time link).

- The key is stored locally on your device in the system preference store
  (`UserDefaults` / `@AppStorage`).
- If you use both the iPhone and Apple Watch app, the key may be
  transferred between the two over Apple's encrypted Watch Connectivity
  channel so the watch can make requests on its own.
- The key is sent only to 511.org (or our proxy, see below) as part of
  normal API requests. It is not transmitted anywhere else and is not
  included in telemetry.
- You can clear the key at any time from the in-app Settings screen.

### 3. Favorites, pinned stops, and commute stops

Stops you mark as favorites, pin to the home screen, or assign as your
morning/afternoon commute stop are stored locally on your device:

- in `UserDefaults`, and
- in a shared App Group container so the watch face complication can read
  them without a network call.

These records contain only the stop's identifier and basic metadata (name,
agency, location coordinates of the stop itself). They are **not**
uploaded to our servers. Deleting the App removes them from your device.

### 4. Diagnostic telemetry (anonymous, opt-in by build)

Builds of the App that are configured with a telemetry endpoint send a
small amount of anonymous diagnostic data so we can tell whether requests
to 511.org are succeeding. (Builds without that endpoint configured —
including any open-source build you compile yourself — never send
telemetry.)

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

If you would prefer not to send telemetry at all, you can build the App
from source (see the project's GitHub repository) without configuring a
telemetry endpoint, or contact us at the address above and we will delete
all events associated with your install ID.

### 5. Siri and Shortcuts

If you set up Siri voice commands or Shortcuts for the App:

- Phrases you record are processed by Apple's Siri service under
  [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).
- The App "donates" intents (e.g. "find nearby stops", "check the 38
  bus") to the system so Siri can suggest them. These donations stay on
  your device and are governed by Apple.
- We do not receive transcripts or audio.

### 6. System logs

The App writes routine diagnostic messages to the standard Apple
unified logging system (`os.Logger`). These logs live on your device,
follow Apple's privacy redaction rules, and are only shared with us if
you choose to send a sysdiagnose or crash report through Apple. We do
not collect them automatically.

## Third parties we send data to

| Recipient | What is sent | Why |
|-----------|--------------|-----|
| **511.org Transit API** (operated by the Metropolitan Transportation Commission) | Your latitude/longitude when looking up nearby stops, the stop code when looking up arrivals, and your 511.org API key. | To fetch transit data. Governed by the [511.org terms of use](https://511.org/about/terms-of-use). |
| **Cloudflare (optional proxy)** | The same requests above, with your device's IP address as part of normal HTTP transit, plus an app token header. The proxy adds short-lived caching and forwards to 511.org. | To reduce load on 511.org and add caching. The proxy does not log request bodies or your API key beyond what is required to forward the request. |
| **Apple** | Location permission, Siri intents, Watch Connectivity messages, push of complication updates. | Standard Apple platform services, governed by Apple's Privacy Policy. |

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
  511.org (or our proxy, which forwards it to 511.org).
- No system can be guaranteed 100% secure, but we follow standard Apple
  platform security practices.

## Changes to this policy

We may update this policy from time to time. Material changes will be
reflected by updating the "Effective date" above. Continued use of the
App after a change constitutes acceptance of the updated policy.

## Contact

Questions, requests, or complaints about this Privacy Policy:

**Email:** rlarner@gmail.com
**Repository:** <https://github.com/rularner/SFTransitWatch>
