  - Get registration link working on watch
  - Add stop code entry to iPhone views
  - Stop direction not obvious in list, not easy using voice
  - tag only works on comments, not PR names. But we only validate PR names. Fix that.
  - Version in settings still 1.0
  - Link to add favorite stop
  - Direction pointer to stop
  - Configurable notification on alert(?)
  - End-to-end test using worker branch endpoint
  - Map view on watch?
  - Phone Lock Screen widgets
  - Code Coverage

  Bigger:
  Add camera integration for stop search
  Add iPad app to allow for secrets and easier stop management
  Consider removing API code from app and saving on Cloudflare worker/proxy
  Do full server-side API polling for recently-active watches with push notifications
  Consider figuring out how to allow XCode Cloud build steps to not trigger when non-XCode changes are made (e.g. Cloudflare, docs-only, build-only), but still block if they fail. Do the same for Cloudflare. This should also help with the gatekeeper workflow not blocking while xcode and Cloudflare merge-to-main tasks are running.

  To test:
  Watch widgets

  Tech debt:
  Old AppIntentsTests.swift was deleted because it used `result.dialog`, which
  no longer compiles against the current AppIntents framework. Rewrite tests
  for the GetNextArrivalIntent / OpenStopIntent / GetFavoriteStopsIntent
  intents using the current API.
