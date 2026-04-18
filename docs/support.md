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
