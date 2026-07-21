#!/usr/bin/env bash
# Fetch Antigravity (Gemini / Claude+GPT) quota data from the `agy` CLI's
# local HTTPS server. Reuses an already-running `agy` session if one exists;
# otherwise launches a short-lived one just long enough to read quota, then
# tears it down again.
#
# On any problem this always prints valid JSON (usage data or an error
# object) and always exits 0, so the widget never hangs waiting for input.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    printf '{"error":{"message":"python3 is required for the Antigravity source but was not found on PATH."}}\n'
    exit 0
fi

if ! command -v lsof >/dev/null 2>&1; then
    printf '{"error":{"message":"lsof is required for the Antigravity source but was not found on PATH."}}\n'
    exit 0
fi

dir="$(cd "$(dirname "$0")" && pwd)"
helper="$dir/fetch_antigravity_usage.py"

if [ ! -f "$helper" ]; then
    printf '{"error":{"message":"Antigravity fetch helper script missing at %s."}}' "$helper"
    exit 0
fi

python3 "$helper" || printf '{"error":{"message":"Antigravity fetch helper crashed."}}\n'
