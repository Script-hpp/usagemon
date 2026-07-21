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
#   - On any problem (no providers.json, no usable/non-expired token, no
#     python3, network error) this prints nothing and exits 0 so the caller
#     can show the last-known state / retry.
set -euo pipefail

cfg="${CLINE_PROVIDERS:-$HOME/.cline/data/settings/providers.json}"
[ -r "$cfg" ] || exit 0

# providers.json is nested JSON with one accessToken per provider, so a plain
# sed extraction (like the Claude script uses) is not reliable. Use python3 to
# pick the best non-expired token. python3 is available on virtually all modern
# Linux desktops; if it is missing, silently fall back (exit 0, no output).
command -v python3 >/dev/null 2>&1 || exit 0

tmp=$(mktemp)
chmod 600 "$tmp"
trap 'rm -f "$tmp"' EXIT

# Write the curl Authorization header into the temp file from inside python so
# the token is never exposed through a shell variable or curl's argv.
CLINE_PROVIDERS="$cfg" CLINE_CURL_CONFIG="$tmp" python3 - <<'PY' 2>/dev/null || true
import json, os, time

p = os.environ.get("CLINE_PROVIDERS")
try:
    with open(p) as f:
        d = json.load(f)
except Exception:
    raise SystemExit(0)

provs = d.get("providers") or {}
if not isinstance(provs, dict) or not provs:
    raise SystemExit(0)

now = int(time.time() * 1000)

# Prefer the last-used provider, then try the rest (tokens can expire
# independently per provider, so a fallback to a still-valid one is useful).
lu = d.get("lastUsedProvider")
order = []
if lu and lu in provs:
    order.append(lu)
for k in provs:
    if k not in order:
        order.append(k)

token = None
for name in order:
    settings = (provs.get(name) or {}).get("settings") or {}
    auth = settings.get("auth") or {}
    tok = auth.get("accessToken") or ""
    exp = auth.get("expiresAt") or 0
    if not tok:
        continue
    # Skip tokens that are clearly expired (allow a small clock-skew tolerance).
    if exp and exp < now - 30000:
        continue
    token = tok
    break

if not token:
    raise SystemExit(0)

cfg = os.environ.get("CLINE_CURL_CONFIG")
with open(cfg, "w") as f:
    f.write('header = "Authorization: Bearer %s"\n' % token)
    f.write('header = "Accept: application/json"\n')
PY

# If python did not write a header (no usable token), bail out quietly.
[ -s "$tmp" ] || exit 0

curl -s --max-time 10 --config "$tmp" \
    https://api.cline.bot/api/v1/users/me/plan/usage-limits \
    || true
