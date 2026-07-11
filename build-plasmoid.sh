#!/usr/bin/env bash
# Build a distributable usagemon.plasmoid archive (for uploading to the KDE
# Store / store.kde.org, or for `kpackagetool6 --install usagemon.plasmoid`).
#
# A .plasmoid file is just a zip of the package/ directory contents, with
# metadata.json at the archive root.
set -euo pipefail

cd "$(dirname "$0")"

version=$(grep -oP '"Version"\s*:\s*"\K[^"]+' package/metadata.json)
out="usagemon-${version}.plasmoid"

rm -f "$out"
( cd package && zip -r -q -X "../$out" . -x '*.DS_Store' )

echo "Built $out"
