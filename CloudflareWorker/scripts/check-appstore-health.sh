#!/usr/bin/env bash
# Calls /healthz/appstore on the worker that was just deployed and fails
# (non-zero exit) if either Apple-related credential check is unhealthy.
#
# Picks the target host based on WORKERS_CI_BRANCH (injected by Workers
# Builds): the production branch checks WORKER_HOSTNAME (the custom
# domain that real users hit); any other branch (PR builds) checks
# WORKERS_DEV_URL (the shared *.workers.dev preview URL), since
# WORKER_HOSTNAME isn't repointed for PR deploys.
#
# Required env vars: WORKER_HOSTNAME, WORKERS_DEV_URL, HEALTHCHECK_TOKEN
# Optional env var: WORKERS_CI_BRANCH (treated as non-production if unset)

set -euo pipefail

PRODUCTION_BRANCH="main"

if [[ -z "${WORKER_HOSTNAME:-}" ]]; then
    echo "Missing required environment variable: WORKER_HOSTNAME" >&2
    exit 1
fi
if [[ -z "${WORKERS_DEV_URL:-}" ]]; then
    echo "Missing required environment variable: WORKERS_DEV_URL" >&2
    exit 1
fi
if [[ -z "${HEALTHCHECK_TOKEN:-}" ]]; then
    echo "Missing required environment variable: HEALTHCHECK_TOKEN" >&2
    exit 1
fi

if [[ "${WORKERS_CI_BRANCH:-}" == "$PRODUCTION_BRANCH" ]]; then
    HOST="$WORKER_HOSTNAME"
else
    HOST="$WORKERS_DEV_URL"
fi

URL="https://${HOST}/healthz/appstore"
echo "Checking Apple communication health at $URL"

RESPONSE=$(curl -sS -w '\n%{http_code}' -H "Authorization: Bearer ${HEALTHCHECK_TOKEN}" "$URL")
STATUS="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

echo "$BODY"

if [[ "$STATUS" != "200" ]]; then
    echo "Health check failed with HTTP $STATUS" >&2
    exit 1
fi
