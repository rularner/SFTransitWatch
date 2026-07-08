# GTFS-RT Fixture Capture

This directory holds small, trimmed sample feeds used for golden transparency tests. Fixtures are committed to the repo as compressed snapshots to keep the repo lightweight.

## Capturing Real Data

### Real SIRI StopMonitoring (511.org)

Capture a real SIRI response for a given stop:

```bash
curl -s \
  "https://api.511.org/transit/StopMonitoring?agency=SF&stopCode=16393&api_key=YOUR_API_KEY" \
  -H "Accept-Encoding: gzip" \
  -o stop-monitoring-16393.siri
```

The response is gzip-compressed and contains a UTF-8 BOM. Trim to a few `MonitoredStopVisit` entries to keep file size minimal.

### GTFS-RT Trip Updates (Regional Gateway)

Capture the raw GTFS-RT trip updates feed from the Regional Gateway:

```bash
curl -s \
  "https://api.511.org/transit/tripupdates?agency=RG&api_key=YOUR_API_KEY" \
  -H "Accept-Encoding: gzip" \
  -o tripupdates-rg.pb
```

The response is a gzip-compressed Protocol Buffer (not JSON). Extract a single trip update covering the relevant stop to minimize file size.

## Encoding Notes

- Both responses are gzip-compressed; decompress before use.
- The 511.org API returns UTF-8 with a byte-order mark (BOM: `EF BB BF`); strip before parsing JSON.
- The GTFS-RT feed is binary Protocol Buffer; no BOM handling needed.

## Using Fixtures in Tests

Load fixtures with decompression and BOM handling:

```ts
import fs from "fs";
import zlib from "zlib";

const raw = fs.readFileSync("fixtures/stop-monitoring-16393.siri");
const decompressed = zlib.gunzipSync(raw);
// Strip UTF-8 BOM if present
const trimmed = decompressed[0] === 0xEF && decompressed[1] === 0xBB && decompressed[2] === 0xBF
  ? decompressed.slice(3)
  : decompressed;
const json = JSON.parse(new TextDecoder().decode(trimmed));
```

## Important: API Keys

**Never commit `.env` files, API keys, or bearer tokens.** The golden test uses a hand-built feed; actual API credentials belong in environment variables or secure vaults only.
