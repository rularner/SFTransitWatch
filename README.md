# SF Transit Watch

An Apple Watch + iPhone app that shows nearby transit stops and real-time arrival
times across the Bay Area, backed by the 511.org Open Data API.

## Features

- **Real-time arrivals**: Live predictions from 511.org's `StopMonitoring` API,
  with a scheduled-timetable fallback when real-time data isn't available
- **Seven Bay Area agencies**: Muni, BART, AC Transit, Caltrain, Golden Gate
  Transit, SamTrans, and VTA — filterable in Settings
- **Location-based stop discovery**: Finds nearby stops using GPS, with a
  per-agency search radius (e.g. wider for sparser Caltrain/Golden Gate stops)
- **Favorites**: Star stops for quick access; favorites sort to the top of the list
- **Commute slots + alerts**: Pin a morning and afternoon stop and get a local
  notification when your bus is approaching, with configurable lead time and
  time-of-day window, and automatic suppression once you're already at the stop
- **Watch complications**: Home-screen widgets showing the next arrival for a
  commute slot or for your nearby favorite stops, refreshed in the background
- **iPhone ↔ Watch sync**: API key/token, enabled agencies, commute slots, and
  favorites sync automatically over Watch Connectivity
- **Siri / Shortcuts**: Built on the `AppIntents` framework — "find nearby
  stops" and "check bus times" work out of the box, no shortcut recording needed
- **Two ways to get data**: subscribe to the SF Transit Watch proxy server (no
  API key to manage), or bring your own free 511.org API key and skip our
  servers entirely
- **Watch-optimized UI**: Large touch targets, pull-to-refresh, auto-refresh

## Architecture

This is a single Xcode project with four targets sharing one local Swift package:

- **`SFTransitWatch/`** — iOS companion app. Onboarding, purchases, deep-link
  handling, and hosts the Watch Connectivity session that pushes config to the watch.
- **`SFTransitWatch Watch App/`** — the watchOS app. Same onboarding/purchase
  flow, plus background refresh and the logic that drives complication updates.
- **`SFTransitWatch Complication/`** — WidgetKit extension with two widgets
  (commute-slot arrival, nearby-favorites arrival). Reads snapshots the watch
  app writes to the shared App Group; makes no network calls of its own.
- **`SFTransitWatchPackage/`** — local Swift package holding almost all shared
  model, view, and service code (agencies, favorites, alerts, subscriptions,
  Siri intents, API codecs, etc.) used by both the iOS and watch targets.

Two backend components live in this repo but deploy independently:

- **`CloudflareWorker/`** — proxies and caches 511.org requests at
  `api.sftransitwatch.com`; issues/exchanges worker access tokens for
  subscribers. See `CloudflareWorker/README.md`.
- **`AwsLambda/`** — a two-function pipeline (scheduled feed refresher + an
  on-demand reader behind a Function URL) that decodes 511's GTFS-realtime
  feed for Muni and serves it to the Worker, offloading work the Worker's
  free-tier CPU budget can't cover. See `AwsLambda/README.md`.

## Getting Data: Subscribe or Bring Your Own Key

On first launch the app asks you to pick one:

- **Subscribe to the SF Transit Watch server** (recommended) — an
  auto-renewing App Store subscription. No API key to register or manage,
  plus server-side caching for faster responses. Your requests (location,
  stops you look up) pass through our server.
- **Use a 511.org API key directly** — free, no subscription. Requests go
  straight from the app to 511.org; our servers see nothing.

Full walkthrough, including loading a key via a `sftransitwatch://key/…` link
sent to your watch, is in [docs/support.md](docs/support.md).

## Setup Instructions

### Prerequisites

- Xcode 26 (targets build against the iOS 26.4 / watchOS 26.4 SDKs)
- Apple Developer Account (for device testing)
- iPhone + Apple Watch paired together (recommended; simulators work for most development)
- Optional: a 511.org API key ([free](https://511.org/open-data/token)) if you don't want to use the proxy server

### Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd SFTransitWatch
   ```

2. **Install git hooks**:
   ```bash
   ./bin/install-git-hooks.sh
   ```
   Installs a `commit-msg` hook that enforces Conventional Commits on commit
   subjects (mirroring `.github/workflows/validate-pr-title.yml`'s PR-title
   check) plus a `post-checkout` hook used by worktrees. Hook source lives in
   `.githooks/` since git hooks aren't versioned by git itself; run this
   script once per clone (not per worktree — `.git/hooks` is shared).

3. **(Optional) Override signing locally**:
   ```bash
   cp Developer.xcconfig.sample Developer.xcconfig
   # Edit Developer.xcconfig and fill in YOUR_TEAM_ID and SELF_PROVISION_PRIVATE_KEY
   ```
   `Developer.xcconfig` is gitignored and optional — `Config.xcconfig` pulls it
   in with an optional `#include?` directive, so the project builds fine
   without it. Create it only if you want to override signing settings like
   `DEVELOPMENT_TEAM` or provide the self-provision private key for device
   builds. See `Developer.xcconfig.sample` for key-generation instructions.

   **Worker proxy (optional):** by default the app prompts on first launch to
   connect to the SF Transit Watch proxy server (auto-provisioned, no operator
   action required) or enter a direct 511.org API key. If you prefer to
   distribute tokens manually (e.g. to specific family members without the
   first-launch prompt), you can mint a bootstrap link:

   1. The worker operator mints a link for a specific device:
      ```bash
      cd CloudflareWorker
      WORKER_URL=https://your-worker.workers.dev ./scripts/issue-token.sh <your-device-label>
      ```
      The script prints a link of the form
      `sftransitwatch://wt?u=<encoded-worker-url>&c=<one-time-code>`
      (see `WorkerConfigLink.workerBootstrap`; the worker URL must be
      `https`, and the parameter is `c`, a one-time code — not the token
      itself, which is exchanged for on first use).
   2. They share the link via Messages or Mail, then open it on the device.
      The app handles the link directly on both iOS and watchOS. Settings
      will then show the worker host instead of "Not set". Note that some
      mail and message clients won't auto-linkify a non-`https` URL, so it
      may arrive as plain, untappable text.
   3. To revoke later (lost device, leaked token), the operator runs
      `npx wrangler kv key delete --binding CLIENT_TOKENS <hash>`.

4. **Open in Xcode**:
   ```bash
   open SFTransitWatch.xcodeproj
   ```

5. **Configure your team**:
   - Select the project in Xcode
   - Go to "Signing & Capabilities"
   - Select your development team
   - Update the bundle identifier if needed

6. **Build and Run**:
   - Select the `SFTransitWatch` (iPhone) or `SFTransitWatch Watch App` scheme
   - Press Cmd+R to build and run

7. **Configure data source**:

   On first launch the app will prompt you. Pick whichever is easiest:

   - **Subscribe to the proxy server** (recommended): tap **Subscribe** on
     the first-launch prompt. The app self-provisions a token automatically
     once the subscription is active — no API key needed.
   - **Direct 511.org**: on the first-launch prompt, tap
     **Use 511.org key instead**, then paste your API key in the Settings
     sheet that opens.
   - **Via text or email (watch/phone)**: send yourself a link
     `sftransitwatch://key/YOUR_API_KEY` and open it on your Apple Watch to
     load the key directly. The key goes after a slash, not as a `?k=`
     parameter.

   See [docs/support.md](docs/support.md) for more detail.

### Location Permissions

The app requires location access to find nearby stops. When prompted, tap
"Allow While Using App" and it will automatically start finding nearby stops.

## Project Structure

```
SFTransitWatch/
├── SFTransitWatch/                        # iOS companion app target
│   ├── SFTransitWatchApp.swift            # App entry point, onboarding, deep links
│   ├── ContentView.swift                  # Root navigation
│   ├── BusStopListView.swift              # Nearby/favorite stops list
│   ├── BusArrivalView.swift               # Arrival times for a selected stop
│   ├── BusJourneyView.swift               # Onward-stop journey view
│   ├── SettingsView.swift                 # API key, agencies, favorites management
│   ├── SiriManager.swift                  # Siri/AppIntents wiring
│   ├── TransitAPI.swift                   # 511.org / worker-proxy API client
│   └── PhoneSession.swift                 # Watch Connectivity session (phone side)
├── SFTransitWatch Watch App/              # watchOS app target
│   ├── SFTransitWatchApp.swift            # App entry point, onboarding, deep links
│   ├── AppDelegate.swift
│   ├── ContentView.swift
│   ├── BusStopListView.swift
│   ├── BusArrivalView.swift
│   ├── SettingsView.swift
│   ├── TransitAPI.swift                   # 511.org / worker-proxy API client (watch)
│   ├── WatchSiriManager.swift
│   ├── WatchSession.swift                 # Watch Connectivity session (watch side)
│   ├── BackgroundRefreshController.swift  # Background refresh + alert notifications
│   └── ComplicationUpdater.swift          # Writes snapshots for the widget extension
├── SFTransitWatch Complication/           # WidgetKit extension target
│   ├── ComplicationWidget.swift           # Commute-slot arrival widget
│   └── NearbyFavoritesWidget.swift        # Nearby-favorites arrival widget
├── SFTransitWatchPackage/                 # shared Swift package (most of the logic)
│   └── Sources/SFTransitWatchPackage/
│       ├── Agency.swift                   # Bay Area transit agency definitions
│       ├── BusStop.swift / BusArrival.swift / OnwardStop.swift
│       ├── TransitCodecs.swift            # JSON decoding of 511's SIRI-shaped responses
│       ├── SIRIXMLParser.swift            # XML parsing for service-alert text
│       ├── FavoritesManager.swift / SharedAgenciesManager.swift
│       ├── CommuteSlotsManager.swift / CommuteSlotPickerView.swift
│       ├── AlertSettingsManager.swift / AlertSlotSettingsView.swift
│       ├── SubscriptionManager.swift / PaywallView.swift / SubscriptionDisplayInfo.swift
│       ├── SelfProvisionService.swift / WorkerConfigLink.swift / WorkerTokenExchange.swift
│       ├── ConfigurationManager.swift / ProvisionRefreshGate.swift
│       ├── SiriIntents.swift / SiriShortcutsView.swift
│       ├── StopRoutesCache.swift / Telemetry.swift
│       └── LocationManager.swift / LocationProvider.swift
├── CloudflareWorker/                      # 511.org proxy + token issuance (deploys to api.sftransitwatch.com)
├── AwsLambda/                             # GTFS-RT feed refresher + reader behind the Worker
└── docs/                                  # GitHub Pages site (www.sftransitwatch.com)
```

## Backend Components

### Cloudflare Worker

Proxies and caches 511.org requests at `api.sftransitwatch.com`. Handles
`/self-provision` (issues a worker token after verifying an App Store
subscription), `/worker-token` (exchanges a one-time bootstrap code for a
token), telemetry ingestion, and the proxied transit endpoints. `/StopMonitoring`
for Muni is served by the AWS Lambda pipeline rather than calling 511.org
directly. See `CloudflareWorker/README.md`.

### AWS Lambda GTFS-RT pipeline

Two Lambda functions, deployed via GitHub Actions OIDC: a scheduled refresher
that decodes 511's regional GTFS-realtime feed every 2 minutes and writes a
snapshot to S3, and a reader behind a Function URL (gated by a shared-secret
header) that the Worker calls to serve real-time Muni arrivals. This exists
because decoding GTFS-RT inline exceeded the Worker's free-tier CPU budget.
See `AwsLambda/README.md`.

## 511.org API Integration

### Supported Transit Agencies

- **Muni** — San Francisco Municipal Transportation Agency
- **BART** — Bay Area Rapid Transit
- **AC Transit** — Alameda-Contra Costa Transit
- **Caltrain** — Peninsula commuter rail
- **Golden Gate Transit** — Marin/Sonoma buses and ferries
- **SamTrans** — San Mateo County Transit District
- **VTA** — Santa Clara Valley Transportation Authority

### API Endpoints Used

- **StopMonitoring**: real-time arrival predictions
- **Stops**: nearby stop search
- **StopTimetable**: scheduled-arrival fallback and per-stop route discovery
- **Timetable**: onward-stop journey lookup

### Data Format

The primary path decodes 511.org's SIRI-shaped **JSON** responses directly
(`TransitCodecs.swift`). A regex-based XML parser exists as a last-resort
fallback if a JSON response fails to decode or comes back empty, and a small
XML parser (`SIRIXMLParser.swift`) is used separately for service-alert text.
In worker-proxy mode, requests go to `{workerBaseURL}/{endpoint}` with an
`X-App-Token` header; in direct mode they go to
`https://api.511.org/transit/{endpoint}` with an `api_key` query param. The
app falls back from worker to direct mode automatically on a 401.

## Rate Limits

511.org's API is rate limited (see their documentation for current limits).
Requests are cached on-device (with a short throttle and "keep last on error"
behavior) to minimize calls; subscribers additionally benefit from the
Worker's edge cache.

## Troubleshooting

### Common Issues

1. **"A 511.org API key or registered server is required"**: the app hasn't
   been configured yet. Tap **Connect** to subscribe, or paste a 511.org key
   into Settings. If the watch shows this but the iPhone app is installed,
   configure it there first — the watch picks it up automatically.

2. **No stops found**:
   - Confirm you're inside 511.org's coverage area (the nine Bay Area counties)
   - Check location permissions
   - Check your API key/subscription is configured
   - Try pulling to refresh

3. **Complication isn't updating**: complications refresh on a schedule set
   by watchOS; opening the watch app forces a refresh. If it's still stale
   after a minute, remove and re-add it to the watch face.

4. **Arrivals look stale**: real-time data comes from 511.org's upstream
   feed — if it's delayed, pull to refresh and try again in a minute.

5. **Build errors**: clean the build folder (Cmd+Shift+K), make sure Xcode
   matches the SDKs referenced above, and check the deployment target.

See [docs/support.md](docs/support.md) for the full troubleshooting guide.

## Snapshot tests for App Store screenshots

Goldens at `SFTransitWatchUITests/Goldens/*.png` are App Store deliverables AND regression baselines. The four watch screens (`BusStopListView`, `BusArrivalView`, `SettingsView`, `StopCodeEntryView`) are captured via `XCUIScreen.main.screenshot()` from `SFTransitWatchUITests`. The watch app launches under a `-SNAPSHOT_MODE` flag that routes data fetches through `SnapshotMode` fixtures — no live 511.org calls.

Goldens live alongside the test source so they ride inside the `.xctest` bundle as resources. The test process loads them via `Bundle(for:)`, which is the only path that works on Xcode Cloud — the build step's source tree and env vars don't propagate to the test step there.

The diff comparison ignores the top 200 px of every screenshot — that band contains the watchOS system time and the navigation title row, both of which shift between runs. The full PNG is still saved as the golden so the App Store deliverable looks like a real watch screen.

### Running the tests

Use the wrapper script. It wipes the project's DerivedData before invoking `xcodebuild`, which is the only reliable way to avoid the watchOS simulator's `Unknown application display identifier` install failure between runs:

```bash
bin/run-watch-snapshot-tests.sh
```

To run a single test:

```bash
bin/run-watch-snapshot-tests.sh \
  -only-testing:SFTransitWatchUITests/WatchSnapshotUITests/testSnapshot_StopCodeEntry
```

Plain `xcodebuild test` from the command line and `Cmd+U` from Xcode both also have a scheme test pre-action that erases the watch simulator first (logged to `/tmp/sftransit-preaction.log`), but `simctl erase` alone is not always enough — when in doubt, use the wrapper.

### When a test fails

On a snapshot diff failure, two artifacts land in `$TMPDIR/SFTransitWatchSnapshots/`:

- `<name>-failed.png` — the new full-screen render.
- `<name>-diff.png` — magenta-on-dimmed-grayscale visualization of the differing pixels.

Both are also attached to the test result via `XCTAttachment` (durable across CI), so on Xcode Cloud you can open them from the build's test results view.

The failure message reports the differing-pixel count, the percentage, the bounding box (in cropped coordinates — `y=0` is row 200 of the original screenshot), and the on-disk paths.

### Re-recording after intentional UI changes

```bash
RECORD_SNAPSHOTS=1 bin/run-watch-snapshot-tests.sh
```

The wrapper sets `SIMCTL_CHILD_RECORD_SNAPSHOTS=1` so the env var propagates through `xcodebuild` into the simulator's test process. Review the regenerated PNGs in `SFTransitWatchUITests/Goldens/` and commit them. The next test build picks them up as bundle resources automatically.

## Snapshot tests (iPhone)

Snapshot tests for the iOS companion app live in `SFTransitWatchPhoneUITests/`.

Run locally:

```bash
bin/run-phone-snapshot-tests.sh
```

Record new goldens (after intentional layout changes):

```bash
RECORD_SNAPSHOTS=1 bin/run-phone-snapshot-tests.sh
```

Goldens are stored in `SFTransitWatchPhoneUITests/Goldens/` and committed to the repo for CI reproducibility.

## StoreKitTest (subscription tests)

`SFTransitWatchPhoneTests/SubscriptionManagerTests.swift` uses `StoreKitTest`
(`WorkerProxySubscription.storekit`) to exercise `SubscriptionManager`
against a local StoreKit config. This bundle is **iOS-only** — it launches
the `SFTransitWatch` host app, which `StoreKitTest` requires.

The `SFTransitWatch Watch App` test scheme marks `SFTransitWatchPhoneTests`
as `skipped`. Running it there launches the iOS host app against a watchOS
destination, which crashes before XCTest can attach (`SIGILL`, "Early
unexpected exit"). Don't flip `skipped` back to `NO` on that scheme — run
these tests via the `SFTransitWatch` (iPhone) scheme only.

**Known issue:** `testActiveOriginalTransactionIdReturnsIdAfterPurchase` and
`testPurchaseReturnsOriginalTransactionId` are currently marked
`XCTSkipIf(true, ...)` — `Product.products(for:)` returns `productNotFound`
because `SKTestSession(contentsOf:)` alone doesn't register the product
catalog. Fixing this requires setting the `SFTransitWatch` scheme's Test
action "StoreKit Configuration" to `WorkerProxySubscription.storekit`, then
removing the `XCTSkipIf` lines.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run the relevant test suites (see `CLAUDE.md` for scheme/destination details)
5. Submit a pull request with a [Conventional Commits](https://www.conventionalcommits.org/) title — `.github/workflows/validate-pr-title.yml` enforces this

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Support

- **Using the app**: see [docs/support.md](docs/support.md) for setup and troubleshooting
- **Bugs, feature requests, or anything else**: email sftransitwatch@larner.org
- **Security vulnerabilities**: see [SECURITY.md](SECURITY.md) — please don't open a public issue for these
- **511.org API issues**: those are upstream of this project; contact 511.org directly

---

**Note**: This app uses the 511.org Open Data API. Please respect their terms
of service and rate limits.
