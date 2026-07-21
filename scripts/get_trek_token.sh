#!/usr/bin/env bash
# Logs into a Trek server and writes the resulting session token into .env
# as TREK_SESSION_TOKEN, for manual/exploratory API testing against the
# real backend contract (see .env.example, docs/networking-auth.md).
#
# Run this yourself. If TREK_EMAIL and TREK_PASSWORD are set in .env, it
# uses those; otherwise it prompts interactively (password entry is hidden
# and never written to disk or shell history). This script never writes
# your password anywhere — only you can put it in .env, by editing the
# file directly.
#
# Usage: ./scripts/get_trek_token.sh

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ENV_FILE=.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "No .env file found. Copy .env.example to .env and set TREK_SERVER_URL first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ -z "${TREK_SERVER_URL:-}" ]]; then
  echo "TREK_SERVER_URL is not set in .env." >&2
  exit 1
fi

if [[ -z "${TREK_EMAIL:-}" ]]; then
  read -r -p "Trek email: " TREK_EMAIL
fi
if [[ -z "${TREK_PASSWORD:-}" ]]; then
  read -r -s -p "Trek password: " TREK_PASSWORD
  echo
fi

echo "Logging in as ${TREK_EMAIL} at ${TREK_SERVER_URL}..." >&2

set +e
raw=$(curl -sS -w '\n%{http_code}' -X POST "${TREK_SERVER_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "$(printf '{"email":"%s","password":"%s"}' "$TREK_EMAIL" "$TREK_PASSWORD")")
curl_exit=$?
set -e
unset TREK_PASSWORD

http_code=$(echo "$raw" | tail -n1)
login_response=$(echo "$raw" | sed '$d')
echo "curl exit code: ${curl_exit}, HTTP status: ${http_code}" >&2
echo "Response body: ${login_response}" >&2

if [[ "$curl_exit" -ne 0 ]]; then
  echo "curl failed before getting an HTTP response (exit ${curl_exit})." >&2
  exit 1
fi

extract_token() {
  # Tolerates whitespace after the colon (e.g. "token": "..." vs "token":"...").
  echo "$1" | grep -oE '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/'
}
extract_mfa_token() {
  echo "$1" | grep -oE '"mfa_token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/'
}

token=$(extract_token "$login_response" || true)
mfa_token=$(extract_mfa_token "$login_response" || true)
echo "Extracted token: ${token:-<empty>}, mfa_token: ${mfa_token:-<empty>}" >&2

if [[ -z "$token" && -n "$mfa_token" ]]; then
  read -r -p "MFA code: " mfa_code
  verify_response=$(curl -sS -X POST "${TREK_SERVER_URL}/api/auth/mfa/verify-login" \
    -H "Content-Type: application/json" \
    -d "$(printf '{"mfa_token":"%s","code":"%s"}' "$mfa_token" "$mfa_code")")
  echo "MFA verify response: ${verify_response}" >&2
  token=$(extract_token "$verify_response" || true)
fi

if [[ -z "$token" ]]; then
  echo "Could not find a token in the response above (HTTP ${http_code})." >&2
  exit 1
fi

if grep -q '^TREK_SESSION_TOKEN=' "$ENV_FILE"; then
  # macOS/BSD sed requires an explicit (empty) backup suffix for -i.
  sed -i '' "s|^TREK_SESSION_TOKEN=.*|TREK_SESSION_TOKEN=${token}|" "$ENV_FILE"
else
  echo "TREK_SESSION_TOKEN=${token}" >> "$ENV_FILE"
fi

echo "Saved session token to ${ENV_FILE}."
