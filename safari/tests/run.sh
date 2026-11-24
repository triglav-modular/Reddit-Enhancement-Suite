#!/bin/bash
# Checks the Safari build in WebKit's own web-extension runtime against an
# archived old.reddit page (see harness/main.swift).
#   safari/tests/run.sh            build the extension, then test it
#   safari/tests/run.sh --no-build test the existing dist/safari
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/safari/tests"
OUT="$ROOT/dist/safari-harness"
# A logged-out old.reddit listing with image posts, from the Wayback Machine
# (old.reddit itself now asks every logged-out client to log in).
FIXTURE_URL="https://web.archive.org/web/20260101022858id_/https://old.reddit.com/r/EarthPorn/"
PAGE_URL="https://old.reddit.com/r/EarthPorn/"
FIXTURE="$HERE/fixtures/earthporn.html"

cd "$ROOT"
[ "${1:-}" = "--no-build" ] || corepack yarn once --browsers safari

rm -rf "$OUT"
mkdir -p "$OUT" "$HERE/fixtures"
cp -R "$ROOT/dist/safari" "$OUT/ext"
cp "$HERE/harness/content.js" "$OUT/ext/harness-content.js"
cp "$HERE/harness/background.js" "$OUT/ext/harness-background.js"
/usr/bin/python3 -I - "$OUT/ext/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
m = json.load(open(path))
m["background"]["service_worker"] = "harness-background.js"
script = m["content_scripts"][0]
m["content_scripts"].insert(0, {"matches": script["matches"], "exclude_matches": script["exclude_matches"],
                                "js": ["harness-content.js"], "run_at": "document_start"})
json.dump(m, open(path, "w"), indent=2)
PY

if [ ! -s "$FIXTURE" ]; then
    curl -sfL --compressed -o "$FIXTURE" "$FIXTURE_URL"
fi

swiftc -O -swift-version 5 "$HERE/harness/main.swift" -o "$OUT/harness"
"$OUT/harness" "$OUT/ext" "$FIXTURE" "$PAGE_URL"
