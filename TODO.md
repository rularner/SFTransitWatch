Bugs:
  - Re-enable skipped StoreKit purchase-flow tests (testActiveOriginalTransactionIdReturnsIdAfterPurchase, testPurchaseReturnsOriginalTransactionId) once the SFTransitWatch scheme's Test action StoreKit Configuration is set to WorkerProxySubscription.storekit. Currently XCTSkipIf(true, ...).

Privacy / compliance:
  - No telemetry opt-out. Telemetry.shared sends install_id/platform/version/endpoint/status/latency whenever a worker token+baseURL exist; isEnabled has no user toggle. Add a settings switch and confirm PrivacyInfo.xcprivacy declares the collection.

Quick wins (polish / watch-phone parity):
  - Watch complication to show next bus to nearest stop
  - Add configuration for minimum time-to-stop for morning and evening
  - Add early/late times for morning and evening
  - Add ability to disable alerts
  - Add detection of at stop to disable that stop's alerts for rest of day
  - Add MUNI metro line colors to phone BusArrivalRow (watch has J/K/L/M/N/T/F/S colors; phone uses generic hash fallback)
  - Stop direction not obvious in list, not easy using voice
  - tag only works on comments, not PR names. But we only validate PR names. Fix that.
  - Link to share/add favorite stop (help text or button explaining how to star a stop)
  - End-to-end test using worker branch endpoint
  - Code Coverage

Medium features:
  - Phone lock screen widgets (complication target exists; add .accessoryRectangular / .accessoryCircular variants)
  - Favorite stop management (no way to reorder, view, or remove individual favorites; only "clear all"); include custom per-stop names
  - Configurable notification on alert, add alert to phone (see also phone haptic item above)
  - Map view on watch (watchOS 10 has SwiftUI Map; show nearby stops)
  - Service alerts from 511.org (delays/reroutes/shutdowns) — distinct from commute alerts; not yet surfaced
  - Surface 511 rate-limit / quota errors (429) to the user as a "rate limited, back off" state instead of the generic error state (free tier is 1,000 req/day) — verify current behavior first
  - Accessibility audit: accessibilityLabel/Hint only in ~8 views; Dynamic Type (dynamicTypeSize/minimumScaleFactor) only in ArrivalComponents. Make VoiceOver + Dynamic Type coverage consistent across watch views
  - Localization decision: no .strings/.xcstrings, no NSLocalizedString — all UI strings hardcoded English. Decide English-only vs. i18n (SF has large Spanish/Chinese ridership)
  - Offline mode: cache last-known arrivals/stops so the app shows stale-but-useful data with no signal

Siri / voice:
  - Voice feedback (TTS) for arrival times — read the next arrival aloud (natural watch/Siri fit)
  - Advanced / multi-route voice queries (e.g. "when's the next 38 or 5") beyond today's single-route intents

Bigger:
  Real-time vehicle tracking (511 VehicleMonitoring feed; pairs with the watch map view)
  Route / trip planning via 511.org (get me from A to B)
  Add camera integration for stop search (Vision framework OCR on stop shelter sign → stop code)
  Add iPad app to allow for secrets and easier stop management
  Do full server-side API polling for recently-active watches with push notifications
  Consider figuring out how to allow XCode Cloud build steps to not trigger when non-XCode changes are made (e.g. Cloudflare, docs-only, build-only), but still block if they fail. Do the same for Cloudflare. This should also help with the gatekeeper workflow not blocking while xcode and Cloudflare merge-to-main tasks are running.
