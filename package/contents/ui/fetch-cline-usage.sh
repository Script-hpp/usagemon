#!/usr/bin/env bash
# Fetch Cline usage limits from api.cline.bot, reusing the existing local
# Cline login that the `cline` CLI already established.
#
# Privacy ("safe auth token"):
#   - The access token is read from ~/.cline/data/settings/providers.json
#     (the file Cline itself writes) and is sent ONLY to api.cline.bot.
#   - The token never enters a shell variable, never appears on the command
#     line (so it is not visible via `ps`), is never printed, logged, or
#     written anywhere except a chmod-600 temp file that is removed right
#     after curl finishes.
#   - On any problem this always prints valid JSON (usage data or a
#     token-free error object) and always exits 0, so the widget never
#     hangs waiting for input.
set -uo pipefail

cfg="${CLINE_PROVIDERS:-$HOME/.cline/data/settings/providers.json}"
if [ ! -r "$cfg" ]; then
    printf '{"error":{"message":"No Cline account found in ~/.cline. Log in with cline first."}}\n'
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf '{"error":{"message":"python3 is required for the Cline source but was not found on PATH."}}\n'
    exit 0
fi

# Find the companion Python helper script (same directory as this bash script).
dir="$(cd "$(dirname "$0")" && pwd)"
helper="$dir/fetch_cline_usage.py"

if [ ! -f "$helper" ]; then
    printf '{"error":{"message":"Cline fetch helper script missing at %s."}}' "$helper"
    exit 0
fi

tmp=$(mktemp) && chmod 600 "$tmp" || {
    printf '{"error":{"message":"Could not create temporary file for the Cline request."}}\n'
    exit 0
}
trap 'rm -f "$tmp"' EXIT

CLINE_PROVIDERS="$cfg" CLINE_CURL_CONFIG="$tmp" python3 "$helper" || true

if [ ! -s "$tmp" ]; then
    printf '{"error":{"message":"No usable Cline account token found. Log in again with the Cline CLI (cline)."}}\n'
    exit 0
fi

curl -s --max-time 10 --config "$tmp" \
    https://api.cline.bot/api/v1/users/me/plan/usage-limits \
    || printf '{"error":{"message":"Could not reach the Cline usage API."}}\n'

