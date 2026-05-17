#!/usr/bin/env bash
# Issue a per-device worker auth token.
#
# Two KV entries are written to CLIENT_TOKENS:
#   reg:<CODE>   -> raw TOKEN, TTL 4 hours  (one-time exchange code for the device)
#   SHA256(TOKEN)-> {label, createdAt}     (permanent auth record used on every request)
#
# The bootstrap link carries only the one-time CODE, not the raw TOKEN, so the
# token is never in a URL that could be logged or shared accidentally.
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
ENCODED_URL=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$WORKER_URL")

# Permanent token — never leaves the server after this script runs.
TOKEN=$(openssl rand -hex 32)
HASH=$(printf '%s' "$TOKEN" | shasum -a 256 | awk '{print $1}')
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# One-time registration code — carried in the bootstrap link, redeemed once for TOKEN.
CODE=$(openssl rand -hex 16)

# 1. Store the permanent auth record (hash → metadata).
npx wrangler kv key put --binding CLIENT_TOKENS "$HASH" \
    "$(printf '{"label":"%s","createdAt":"%s"}' "$LABEL" "$CREATED_AT")" >/dev/null

# 2. Store the one-time exchange code (reg:<code> → token), expires in 4 hoursutes.
npx wrangler kv key put --binding CLIENT_TOKENS "reg:${CODE}" "$TOKEN" \
    --expiration-ttl 14400 >/dev/null

echo "Issued token for label: $LABEL"
echo "  worker URL:       $WORKER_URL"
echo "  token hash:       $HASH"
echo "  code (expires in 4 hours, single use)"
echo
echo "Bootstrap link (send to device via Messages/Mail — tap on iOS or watchOS):"
echo "  sftransitwatch://wt?u=${ENCODED_URL}&c=${CODE}"
echo
echo "To revoke the permanent token later:"
echo "  npx wrangler kv key delete --binding CLIENT_TOKENS $HASH"
