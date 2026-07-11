#!/usr/bin/env bash
# Fetch Claude Code subscription usage from the OAuth usage endpoint, reusing
# the existing local OAuth session that Claude Code already established.
#
# Privacy: the access token is read from Claude Code's own credentials file and
# sent ONLY to api.anthropic.com (the same endpoint the `claude` CLI itself
# calls). It is never stored, copied elsewhere, or printed — only the usage
# JSON is written to stdout. On any problem (no credentials, no token, network
# error) this prints nothing and exits 0 so the caller can fall back to the CLI.
set -euo pipefail

cred="${CLAUDE_CREDENTIALS:-$HOME/.claude/.credentials.json}"
[ -r "$cred" ] || exit 0

# The credentials file is single-line JSON; pull out the OAuth access token
# without needing jq/python (sed is universally available).
token=$(sed -n 's/.*"accessToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cred" | head -n1)
[ -n "$token" ] || exit 0

curl -s --max-time 10 \
    https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    || exit 0
