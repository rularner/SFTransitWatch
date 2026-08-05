---
layout: default
title: Support
---

# Support

## Getting started

### Option A — Subscribe to the SF Transit Watch server (recommended)

On first launch, the app offers to connect to the SF Transit Watch proxy
server. This requires an auto-renewing subscription, purchased through the
App Store; the current price and billing period are shown on the subscribe
screen in the app before you buy. Subscriptions renew automatically unless
cancelled at least 24 hours before the end of the period, and you can manage
or cancel yours any time in **Settings → Apple Account → Subscriptions** on
iPhone.

In exchange you get transit data without registering for or managing an API
key of your own, plus server-side caching so your watch gets faster
responses.

In this mode your requests go through our server, which means it receives
your location and the stops you look up. See the
[privacy policy](privacy_policy.html) for exactly what is sent and kept.

### Option B — Use a 511.org API key directly

SF Transit Watch also works with a free [511.org Open Data API](https://511.org/open-data) key, with no subscription. This mode sends requests directly from the app to 511.org, bypassing our proxy entirely — we receive nothing at all, including no diagnostics. This is the option to choose if you would rather no server of ours ever see your location.

**Getting a key:**

1. Go to [https://511.org/open-data/token](https://511.org/open-data/token).
2. Fill out the short registration form.
3. You'll receive an API token by email, usually within a few minutes.

**Entering your key:**

1. On the first-launch prompt, tap **Use 511.org key instead**.
2. In the Settings screen that opens, paste your token into the **511.org API Key** field.
3. The watch app picks up the key automatically the next time it connects to the phone.

You can also enter the key directly on the watch under **Settings → API Key**, but setting it on the phone is easier.

**If you previously subscribed to the proxy server**, entering an API key is
not on its own enough to stop using it — the app keeps routing through the
server while it still holds a credential for it. To switch fully to direct
mode, also tap **Clear** under **Settings → Worker proxy**. Once cleared, the
app talks only to 511.org. (Clearing the credential does not cancel your
subscription; cancel that in **Settings → Apple Account → Subscriptions**.)

## Loading your API key via text or email

If you'd rather not type or paste the key into the watch, you can send yourself a link and tap it on your wrist.

1. Send yourself a Messages or email message containing a link in this exact form:

   ```
   sftransitwatch://key/YOUR_API_KEY
   ```

   Replace `YOUR_API_KEY` with the token 511.org sent you. Note the key goes **after a slash**, not as a `?k=` parameter.

2. Open that message **on your Apple Watch**:
   - **Messages:** open the conversation in the Messages app on the watch.
   - **Mail:** open the email in the Mail app on the watch (requires Mail to be set up on the watch — see Apple's [Use Mail on Apple Watch](https://support.apple.com/guide/watch/mail-apd8a5e88eb9/watchos) guide).

3. Tap the link. The watch will launch SF Transit Watch, save the key, and you'll be ready to go.

The key is never sent anywhere except your own watch — the link is handled entirely on-device and never resolves against any web server.

**If the link isn't tappable:** many Mail and Messages clients only auto-linkify `http`/`https` URLs, so an `sftransitwatch://` link may render as plain text you can't tap. If that happens, type the key in directly on the watch under **Settings → API Key**, or set it on the iPhone and let it sync over.

## Troubleshooting

### The app shows "A 511.org API key or registered server is required"

The app hasn't been configured yet. Open the app on iPhone (or watch), and either:

- Tap **Connect** to connect to the SF Transit Watch proxy server automatically, or
- Go to **Settings** and paste a 511.org API key into the **511.org API Key** field.

If the iPhone app is installed and the watch shows this message, open the iPhone app first and configure it there. The watch picks up the configuration automatically via Watch Connectivity.

### No nearby stops appear

- Make sure you've granted location permission to the watch app.
- Confirm you're inside the 511.org coverage area (the nine Bay Area counties).
- Check that your 511 API key is configured.

### Arrivals look stale

Real-time data is provided directly by 511.org. If arrival times look off, the upstream feed may be delayed; pull to refresh and try again in a minute.

### Complication isn't updating

Complications refresh on a schedule set by watchOS. Opening the watch app forces a refresh. If the complication still shows old data after a minute, remove and re-add it to the watch face.

## Contact

For bug reports, feature requests, or anything else, email **sftransitwatch@larner.org**.
