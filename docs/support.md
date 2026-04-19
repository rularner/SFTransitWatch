---
layout: default
title: Support
---

# Support

## Getting a 511.org API key

SF Transit Watch uses the free [511.org Open Data API](https://511.org/open-data) for real-time arrivals. You'll need a free API token:

1. Go to [https://511.org/open-data/token](https://511.org/open-data/token).
2. Fill out the short registration form.
3. You'll receive an API token by email, usually within a few minutes.

## Entering your API key

1. Open the SF Transit Watch app on your iPhone.
2. Go to **Settings** and paste your token into the **511.org API Key** field.
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

### The watch shows "Please configure your 511.org API key"

Either the key hasn't synced from the phone yet, or it hasn't been set at all. Open the iPhone app, confirm the key is in Settings, then open the watch app and give it a few seconds to receive the update.

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
