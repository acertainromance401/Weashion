#!/bin/sh
# Pulls the Korean source strings the compiler extracted during the last build
# into Localizable.xcstrings, so new keys show up for translation (en / ja).
#
#   1. Build once (Xcode or xcodebuild) so *.stringsdata files exist.
#   2. scripts/sync-localizable-strings.sh [path/to/DerivedData]
#   3. Open Localizable.xcstrings in Xcode and fill in the new English / Japanese rows.
#
# Keys that disappeared from code are marked "stale" rather than deleted.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$ROOT/weashion/Localizable.xcstrings"
DERIVED="${1:-$HOME/Library/Developer/Xcode/DerivedData}"

STRINGSDATA=$(find "$DERIVED" -path '*/weashion.build/Objects-normal/*' -name '*.stringsdata' 2>/dev/null | grep -v 'Tests.build' || true)
if [ -z "$STRINGSDATA" ]; then
  echo "No .stringsdata files under $DERIVED — build the weashion scheme first." >&2
  exit 1
fi

# shellcheck disable=SC2086
xcrun xcstringstool sync "$CATALOG" --stringsdata $STRINGSDATA
xcrun xcstringstool print "$CATALOG" | wc -l | sed 's/^ *//; s/$/ keys in Localizable.xcstrings/'
