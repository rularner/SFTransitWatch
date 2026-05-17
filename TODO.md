Quick wins (polish / watch-phone parity):
  - Wire up stop code entry on iPhone (StopCodeEntryView exists, showingStopCodeEntry state exists, no trigger button)
  - Add MUNI metro line colors to phone BusArrivalRow (watch has J/K/L/M/N/T/F/S colors; phone uses generic hash fallback)
  - Stop direction not obvious in list, not easy using voice
  - tag only works on comments, not PR names. But we only validate PR names. Fix that.
  - Link to share/add favorite stop (help text or button explaining how to star a stop)
  - End-to-end test using worker branch endpoint
  - Code Coverage

Medium features:
  - Bus view with list of stops
  - Phone lock screen widgets (complication target exists; add .accessoryRectangular / .accessoryCircular variants)
  - Favorite stop management (no way to reorder, view, or remove individual favorites; only "clear all")
  - Configurable notification on alert, add alert to phone (see also phone haptic item above)
  - Map view on watch (watchOS 10 has SwiftUI Map; show nearby stops)

Bigger:
  Add camera integration for stop search (Vision framework OCR on stop shelter sign → stop code)
  Add iPad app to allow for secrets and easier stop management
  Do full server-side API polling for recently-active watches with push notifications
  Consider figuring out how to allow XCode Cloud build steps to not trigger when non-XCode changes are made (e.g. Cloudflare, docs-only, build-only), but still block if they fail. Do the same for Cloudflare. This should also help with the gatekeeper workflow not blocking while xcode and Cloudflare merge-to-main tasks are running.

To test:
  Watch widgets

Tech debt:
  Old AppIntentsTests.swift was deleted because it used `result.dialog`, which
  no longer compiles against the current AppIntents framework. Rewrite tests
  for the GetNextArrivalIntent / OpenStopIntent / GetFavoriteStopsIntent
  intents using the current API.
