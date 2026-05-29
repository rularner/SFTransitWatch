---
layout: default
title: Support
---

# Support

## Getting started

### Option A — Connect to the SF Transit Watch server (recommended)

On first launch, the app will ask if you want to connect to the SF Transit
Watch proxy server. Tap **Connect** and the app configures itself
automatically — no API key required.

The proxy is optional and free. It caches 511.org requests so your watch
gets faster responses. See the privacy policy for what data is exchanged
during the one-time setup.

### Option B — Use a 511.org API key directly

SF Transit Watch also works with a free [511.org Open Data API](https://511.org/open-data) key. This mode sends requests directly from the app to 511.org, bypassing the proxy entirely.

**Getting a key:**

1. Go to [https://511.org/open-data/token](https://511.org/open-data/token).
2. Fill out the short registration form.
3. You'll receive an API token by email, usually within a few minutes.

**Entering your key:**

1. On the first-launch prompt, tap **Use 511.org key instead**.
2. In the Settings screen that opens, paste your token into the **511.org API Key** field.
3. The watch app picks up the key automatically the next time it connects to the phone.

You can also enter the key directly on the watch under **Settings → API Key**, but setting it on the phone is easier.

## Loading your API key via text or email

If you'd rather not type or paste the key into the watch, you can send yourself a link and tap it on your wrist.

1. Send yourself a Messages or email message containing a link in this exact form:

   ```
   https://rularner.github.io/sftransitwatch/key?k=YOUR_API_KEY
   ```

   Replace `YOUR_API_KEY` with the token 511.org sent you. Messages and Mail will render it as a normal tappable link.

2. Open that message **on your Apple Watch**:
   - **Messages:** open the conversation in the Messages app on the watch.
   - **Mail:** open the email in the Mail app on the watch (requires Mail to be set up on the watch — see Apple's [Use Mail on Apple Watch](https://support.apple.com/guide/watch/mail-apd8a5e88eb9/watchos) guide).

3. Tap the link. The watch will launch SF Transit Watch, save the key, and you'll be ready to go.

Tapping the link on the iPhone or a computer won't open the app — the link is only wired into the watch app. Anyone who lands on that URL in a browser just sees a short "open this on your watch" page; the key is never sent anywhere except the watch.

### Fallback: custom URL scheme

If for some reason the https link isn't working (e.g., your watch hasn't picked up the universal link yet), the app also accepts its own URL scheme:

```
sftransitwatch://key/YOUR_API_KEY
```

Note that many email and message clients won't auto-linkify non-`https` URLs, so the link may render as plain text. Prefer the https form above.

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
