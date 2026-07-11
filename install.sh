#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "kpackagetool6 not found. This widget requires KDE Plasma 6." >&2
    exit 1
fi

if kpackagetool6 --list --type Plasma/Applet 2>/dev/null | grep -q "org.usagemon.claude-usage"; then
    kpackagetool6 --type Plasma/Applet --upgrade package
else
    kpackagetool6 --type Plasma/Applet --install package
fi

echo "Installed. Add 'usagemon' to your panel via right-click > Add Widgets."
