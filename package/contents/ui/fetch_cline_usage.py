#!/usr/bin/env python3
"""Read the Cline account access token from providers.json and write
it into a chmod-600 curl --config file. Called by fetch-cline-usage.sh.

Privacy: the token is read here and written directly into the config file
(it never enters a shell variable, never appears in any process argv, and
is never printed to stdout). Only api.cline.bot receives it in the
Authorization header.
"""
import json, os, time, sys


def main():
    providers_path = os.environ.get("CLINE_PROVIDERS")
    curl_config = os.environ.get("CLINE_CURL_CONFIG")
    if not providers_path or not curl_config:
        sys.exit(0)

    try:
        with open(providers_path) as f:
            data = json.load(f)
    except Exception:
        sys.exit(0)

    provs = data.get("providers") or {}
    if not isinstance(provs, dict) or not provs:
        sys.exit(0)

    now = int(time.time() * 1000)

    # Prefer the last-used provider, then try the rest (tokens can expire
    # independently per provider, so a fallback to a still-valid one is useful).
    lu = data.get("lastUsedProvider")
    order = []
    if lu and lu in provs:
        order.append(lu)
    for name in provs:
        if name not in order:
            order.append(name)

    best_token = None
    for name in order:
        settings = (provs.get(name) or {}).get("settings") or {}
        auth = settings.get("auth") or {}
        tok = auth.get("accessToken") or ""
        expires = auth.get("expiresAt") or 0
        if not tok:
            continue
        # Skip tokens that are clearly expired (allow a small clock-skew
        # tolerance so we don't discard a token that is barely expired).
        if expires and expires < now - 30000:
            continue
        best_token = tok
        break

    if not best_token:
        sys.exit(0)

    with open(curl_config, "w") as f:
        f.write('header = "Authorization: Bearer %s"\n' % best_token)
        f.write('header = "Accept: application/json"\n')


if __name__ == "__main__":
    main()
