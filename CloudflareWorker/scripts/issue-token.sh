#!/usr/bin/env bash
# Generate a per-device worker auth token, register its SHA-256 hash in
# the CLIENT_TOKENS KV namespace, and print a worker bootstrap link that
# carries both the worker URL and the raw token. Hand that link to the
# device via Messages/Mail; on iOS, paste it into Settings; on watchOS,
# tap it.
#
# Usage:
#   scripts/issue-token.sh <label> [<worker-url>]
#   WORKER_URL=https://my.workers.dev scripts/issue-token.sh <label>
#
#   <label>      short identifier, e.g. "rusty-watch" or "mom-iphone"
#   <worker-url> https://-prefixed worker base URL. Required (env or arg).
#
# Run from the CloudflareWorker/ directory.

set -euo pipefail

LABEL=${1:-}
WORKER_URL=${WORKER_URL:-${2:-}}

if [[ -z "$LABEL" ]]; then
    echo "usage: $0 <label> [<worker-url>]" >&2
    exit 2
fi
if [[ -z "$WORKER_URL" ]]; then
    echo "worker URL is required (set WORKER_URL env or pass as 2nd arg)" >&2
    exit 2
fi
if [[ "$WORKER_URL" != https://* ]]; then
    echo "worker URL must start with https:// (got: $WORKER_URL)" >&2
    exit 2
fi

if ! command -v openssl >/dev/null; then
    echo "openssl is required" >&2
    exit 1
fi

if ! command -v shasum >/dev/null; then
    echo "shasum is required" >&2
    exit 1
fi

# URL-encode the worker URL so it survives the query-string round trip.
# python3 ships with macOS and is on every CI image we care about.
ENCODED_URL=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$WORKER_URL")

TOKEN=$(openssl rand -hex 32)
HASH=$(printf '%s' "$TOKEN" | shasum -a 256 | awk '{print $1}')
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VALUE=$(printf '{"label":"%s","createdAt":"%s"}' "$LABEL" "$CREATED_AT")

npx wrangler kv key put --binding CLIENT_TOKENS "$HASH" "$VALUE" >/dev/null

echo "Registered token for label: $LABEL"
echo "  worker URL:       $WORKER_URL"
echo "  hash (KV key):    $HASH"
echo
echo "Bootstrap link (paste into iOS Settings, or tap on watchOS):"
echo "  https://rularner.github.io/sftransitwatch/wt?u=${ENCODED_URL}&t=${TOKEN}"
echo
echo "To revoke later:"
echo "  npx wrangler kv key delete --binding CLIENT_TOKENS $HASH"
