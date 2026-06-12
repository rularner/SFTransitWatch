#!/usr/bin/env bash
# Configures a Cloudflare WAF Rate Limiting rule that fires BEFORE the Worker runs.
# Blocked requests are billed as rule evaluations (~$0.05/10k) rather than Worker
# invocations (~$0.30/million), making this cheaper than the in-Worker KV rate limiting.
#
# Required environment variables:
#   CF_API_TOKEN   — Cloudflare API token with Zone:WAF:Edit permission
#   CF_ZONE_ID     — Zone ID for the domain (Cloudflare dashboard → Overview → right sidebar)
#   WORKER_HOSTNAME — The custom domain the Worker is deployed on (e.g. api.yourdomain.com)
#
# Usage:
#   CF_API_TOKEN=... CF_ZONE_ID=... WORKER_HOSTNAME=api.yourdomain.com ./scripts/setup-waf-rate-limits.sh

set -euo pipefail

: "${CF_API_TOKEN:?CF_API_TOKEN must be set}"
: "${CF_ZONE_ID:?CF_ZONE_ID must be set}"
: "${WORKER_HOSTNAME:?WORKER_HOSTNAME must be set}"

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required — brew install jq" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }

BASE="https://api.cloudflare.com/client/v4"
RULE_DESC="sftransitwatch: per-IP flood protection"
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

rule=$(jq -nc \
  --arg host "$WORKER_HOSTNAME" \
  --arg desc "$RULE_DESC" \
  '{
    action: "block",
    description: $desc,
    expression: ("http.host eq \"" + $host + "\""),
    ratelimit: {
      characteristics: ["cf.colo.id", "ip.src"],
      period: 10,
      requests_per_period: 50,
      mitigation_timeout: 10
    }
  }')

echo "Checking existing rate limiting ruleset for zone ${CF_ZONE_ID}..."
http_status=$(curl -s -o "$TMPFILE" -w "%{http_code}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "${BASE}/zones/${CF_ZONE_ID}/rulesets/phases/http_ratelimit/entrypoint")

case "$http_status" in
  200)
    ruleset_id=$(jq -r '.result.id' "$TMPFILE")
    existing_id=$(jq -re --arg d "$RULE_DESC" \
      '.result.rules[] | select(.description == $d) | .id' "$TMPFILE" 2>/dev/null || true)
    if [ -n "$existing_id" ]; then
      echo "Already configured — rule ID: ${existing_id}. Nothing to do."
      exit 0
    fi
    echo "Adding rule to existing ruleset ${ruleset_id}..."
    result=$(curl -s -X POST \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$rule" \
      "${BASE}/zones/${CF_ZONE_ID}/rulesets/${ruleset_id}/rules")
    ;;
  404)
    echo "No rate limiting ruleset found. Creating..."
    result=$(curl -s -X PUT \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"rules\": [${rule}]}" \
      "${BASE}/zones/${CF_ZONE_ID}/rulesets/phases/http_ratelimit/entrypoint")
    ;;
  000)
    echo "Error: curl failed — check connectivity and CF_ZONE_ID" >&2
    exit 1
    ;;
  401|403)
    echo "Error: HTTP ${http_status} — check CF_API_TOKEN has Zone:WAF:Edit permission" >&2
    jq '.errors // .' "$TMPFILE" >&2
    exit 1
    ;;
  *)
    echo "Unexpected HTTP ${http_status} from Cloudflare API" >&2
    jq '.errors // .' "$TMPFILE" >&2
    exit 1
    ;;
esac

if [ "$(echo "$result" | jq -r '.success')" != "true" ]; then
  echo "API error:" >&2
  echo "$result" | jq '.errors' >&2
  exit 1
fi

rule_id=$(echo "$result" | jq -r '.result.rules[-1].id')
echo "Done."
echo "  Rule ID:  ${rule_id}"
echo "  Hostname: ${WORKER_HOSTNAME}"
echo "  Limit:    50 requests per 10s per IP per Cloudflare location"
echo "  Action:   block (429) for 10s after limit is exceeded"
