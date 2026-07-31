Bugs:
  - Re-enable skipped StoreKit purchase-flow tests (testActiveOriginalTransactionIdReturnsIdAfterPurchase, testPurchaseReturnsOriginalTransactionId) once the SFTransitWatch scheme's Test action StoreKit Configuration is set to WorkerProxySubscription.storekit. Currently XCTSkipIf(true, ...).
  - [RESOLVED 2026-07-31] Xcode Cloud / local watchOS 26.5 Simulator + Xcode 26.6 hosted-test hangs ("SFTransitWatch Watch App encountered an error (The test runner hung before establishing connection.)") were previously (2026-07-29) misdiagnosed as non-deterministic Apple-side flakiness unrelated to any code change, based on a single-sample bisection. A follow-up investigation on `watchos-hang-reapply` re-ran every checkpoint 2-3x each and bisected cleanly to Telemetry.swift's live-config refactor: `flushLocked()` runs on Telemetry's private background queue and, since the refactor, reads `ConfigurationManager.shared.workerToken`/`.workerBaseURL` (an app-group `UserDefaults` suite) on every flush instead of once at init — putting a `cfprefsd` round-trip on a background thread during the earliest, most fragile window of app launch, right as XCTest's hosted-test bootstrap is trying to establish its connection. Fixed in `27ab8be` by forcing the read back onto the main thread (`Thread.isMainThread` + `DispatchQueue.main.sync` fallback) while keeping it live (preserves the correctness the refactor was for: config changes take effect without relaunch). Verified 3/3 clean on the full branch tip after 0/11 passes pre-fix. Caveat: no direct stack trace of the hang was captured to confirm `cfprefsd` is the literal blocking call — grounded in bisection + the exact thread-affinity diff, not an observed trace; worth another 5-10 verification samples before treating as fully closed.

Code review 2026-07-12 (full app + worker; verified findings):
  Correctness / user-visible — remaining:
  - Worker SIRI DirectionRef carries GTFS-RT codes "IB"/"OB" (or "" when direction_id absent); siri.ts:19 + TransitCodecs.swift:191 display it verbatim as the arrival destination — blank or "IB"/"OB" shown instead of a headsign, opposite directions indistinguishable. Deeper: pass headsign/destination through the snapshot->SIRI translation.
  - BusArrivalView.swift:238 "arriving soon" haptic dedupes on BusArrival.id, but id = fresh UUID() per parse (BusArrival.swift:4), so the haptic re-fires every 30s refresh for the same bus and notifiedArrivalIDs grows unbounded. Fix: derive a stable identity (route+stop+arrivalTime).
  - NearbyFavoritesWidget is unreachable: @main is on the single SFTransitComplicationWidget with no WidgetBundle, and ComplicationUpdater.updateNearby has zero callers. Register it in a WidgetBundle (or delete) — see quick-win "watch complication for nearest stop".
  - Telemetry.shared (Telemetry.swift:62) captures workerToken/workerBaseURL once (let) at first access; isEnabled and the POST token never reflect later provisioning or clearing until relaunch (also keeps POSTing a revoked token after clear). Fix: read config live.
  - Agency.swift:60 EnabledAgencies.parse falls back to [Self.default] where default is the comma-joined "SF,BA,AC,..." string, so a stored "," / whitespace value yields a single bogus "agency code" that matches no Agency and disables all agencies. Fix: fall back to the parsed known list.
  - WatchSession.swift:58 phone-synced key stored in a second store (UserDefaults.standard "511_API_KEY_FROM_PHONE") that TransitAPI.resolvedKey:30 ranks above the app-group key watch Settings edits — clearing/editing the key in watch Settings leaves the stale phone copy winning. Fix: single canonical store.
  - WatchSession.swift:20 / PhoneSession.swift:56 UserDefaults.didChangeNotification observers (object: nil) fire on every write from any suite (ComplicationUpdater writes ~every 30s), generating echoing WatchConnectivity context traffic. Fix: scope observation / debounce / suppress self-writes.

  Efficiency (watch requests / battery — this branch's theme):
  - Watch TransitAPI (Watch App/TransitAPI.swift) is a diverged fork of the phone's, missing the 20s throttle cache, in-flight dedup, 429 backoff, keep-last stale cache/softBanner, and format=json/MaximumNumberOfCallsOnwards params. Every trigger hits the network; missing format=json also gives phone vs watch different worker cache keys (index.ts:213-224) doubling upstream 511 fetches. Deeper fix: one shared client in SFTransitWatchPackage.
  - Watch TransitAPI.swift:145: empty real-time arrivals trigger an uncached fetchScheduledDepartures on every poll (schedule valid ~24h), doubling requests during GTFS-RT gaps. Fix: cache schedule client-side.
  - stopLocationUpdates() (LocationManager.swift:44) is never called anywhere; startLocationUpdates runs in onAppear (BusArrivalView:191, BusStopListView:109) with best-accuracy GPS + 5deg heading, so location+compass hardware stays on for the whole session. Fix: stop on disappear / when location tab deselected; use hundred-meter accuracy for nearby list.
  - BusStopListView.swift:114 onChange(currentLocation) re-runs loadNearbyStops (one /Stops per enabled agency) on every 10m GPS tick (distanceFilter=10). Fix: refetch only when moved >100-200m or >60s.
  - Watch TransitAPI.swift:398 searchStops downloads the full agency stop list per agency on every search and filters client-side, no caching. Fix: server-side filter via worker /Stops, or cache the list for the session.
  - snapshot.ts:106 handleStopMonitoring calls loadStopNames on every request (KV get + JSON.parse of full agency stop list + Map build) even on cache hits and when visits is empty. Fix: memoize per-isolate with TTL, or skip when visits empty.

  Cleanup / duplication / altitude:
  - Phone TransitAPI.swift:361/400 hand-rolls regex XML parsing (order-dependent, 0.0 default coords) while the watch already uses the shared SIRIXMLParser.parseRecords. Consolidate on the parser.
  - BusArrivalView / BusStopListView duplicated across phone+watch and diverged (watch missing onReceive($pollInterval) countdown + softBanner; phone-only formatDistance/StopCodeEntryView/fetchRoutes/StopRoutesCache/debounced load). Move shared pieces (formatDistance, favorite-toggle + commute-prompt blocks) into SFTransitWatchPackage.
  - Complication views duplicated: NearbyFavoritesEntryView + subviews byte-identical to ComplicationWidgetEntryView (ComplicationWidget.swift:119-209); NearbyFavoritesEntry == NextArrivalEntry minus one field. Parameterize a single entry view.
  - SnapshotMode.isActive threaded through ~15 production call sites instead of injected once at the composition root behind URLSessionProtocol/LocationProvider. Deeper fix: swap in a fixture-backed implementation at startup.
  - Magic constants duplicated: 511 base URL in 4 places (index.ts:4, snapshot.ts:12, both TransitAPI.swift); snapshot.ts:49 re-hardcodes the LAST_UPSTREAM_FETCH_KEY TTL as 6*60*60 instead of the imported STALE_TTL_SECONDS. One exported constant each (latent drift risk today).
  - XCUISnapshotRunner.swift exists 3x (TestSupport/ and both UITest targets), two md5-identical, third differs only in one path component (line 314). Parameterize the directory, keep one canonical file.
  - Dead code: APIError.decodingError/.networkError/.xmlParsingError never thrown (errorKind "parse" branch unreachable in both TransitAPI copies); NextArrivalEntry.unconfigured (ComplicationWidget.swift:24) unreferenced.
  - project.pbxproj:810-976 hardcodes MARKETING_VERSION=1.0 / CURRENT_PROJECT_VERSION=1 in the four test-bundle configs (no baseConfigurationReference), so Config.xcconfig never applies there — pins test bundles at 1.0 regardless of the automated bump. Low severity (test bundles only), but contradicts the CLAUDE.md "MARKETING_VERSION lives in Config.xcconfig" rule.

  Investigated, NOT bugs (do not chase):
  - fromBase64Url padding math (index.ts:743) is correct for all valid inputs; a length ≡1 mod 4 is never valid base64url and both call sites catch the throw.
  - StopTimetable operatorref/monitoringref params are spec-correct; the 412 is 511-side (matches project_gtfsrt_decoder.md investigation).
  - Unconfirmed edge cases: negative-varint decode in the hand-rolled protobuf (malformed-feed only); BusArrialView per-render timer re-creation (runtime-dependent SwiftUI semantics).

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
