#!/usr/bin/env bash
# Generate a per-device worker auth token, register its SHA-256 hash
# in the CLIENT_TOKENS KV namespace, and print the raw token so it can
# be shared with the family member.
#
# Usage: scripts/issue-token.sh <label>
#   <label>  short identifier, e.g. "rusty-watch" or "mom-iphone"
#
# Run from the CloudflareWorker/ directory.

set -euo pipefail

LABEL=${1:-}
if [[ -z "$LABEL" ]]; then
    echo "usage: $0 <label>" >&2
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

TOKEN=$(openssl rand -hex 32)
HASH=$(printf '%s' "$TOKEN" | shasum -a 256 | awk '{print $1}')
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VALUE=$(printf '{"label":"%s","createdAt":"%s"}' "$LABEL" "$CREATED_AT")

npx wrangler kv key put --binding CLIENT_TOKENS "$HASH" "$VALUE" >/dev/null

echo "Registered token for label: $LABEL"
echo "  hash (KV key, safe to keep): $HASH"
echo
echo "Raw token (share via the universal link or paste into Settings):"
echo "  $TOKEN"
echo
echo "Universal link form:"
echo "  https://rularner.github.io/sftransitwatch/wt?t=$TOKEN"
echo
echo "To revoke later:"
echo "  npx wrangler kv key delete --binding CLIENT_TOKENS $HASH"
