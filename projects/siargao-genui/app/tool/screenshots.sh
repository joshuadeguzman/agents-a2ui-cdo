#!/usr/bin/env bash
# Takes the demo screenshots with headless Chrome.
#
# Usage: tool/screenshots.sh [BASE_URL] [OUT_DIR]
#   BASE_URL defaults to http://localhost:8080. Serve a web build there
#   first, for example: (cd build/web && python3 -m http.server 8080)
#   OUT_DIR defaults to ../docs/screens
#
# Works the same against an offline build or a live build; the build decides.
#
# Headless Chrome on macOS will not make a window narrower than about 500 px,
# so phone sized shots load the app in a 390 by 844 iframe (from a throwaway
# local server) and crop the result.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL="${1:-http://localhost:8080}"
OUT_DIR="${2:-$APP_DIR/../docs/screens}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
BUDGET="${BUDGET:-15000}"
HARNESS_PORT="${HARNESS_PORT:-8099}"
TMP_DIR="$(mktemp -d)"
mkdir -p "$TMP_DIR/www"

# Phone frames must be served over http (a file:// page does not render the
# app inside its iframe in headless Chrome).
python3 -m http.server "$HARNESS_PORT" --bind 127.0.0.1 --directory "$TMP_DIR/www" \
  >/dev/null 2>&1 &
HARNESS_PID=$!
trap 'kill "$HARNESS_PID" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT
sleep 1

mkdir -p "$OUT_DIR"
BASE_URL="${BASE_URL%/}"

# name|query|widths
SHOTS=(
  "chat-text|tab=chat&intent=first_time_trip&view=text|1440 390"
  "chat-a2ui|tab=chat&intent=first_time_trip&view=a2ui|1440 390"
  "chat-both|tab=chat&intent=first_time_trip&view=both|1440"
  "home|tab=home|1440 390"
  "search|tab=search|1440 390"
  "gallery|tab=gallery|1440 390"
)

capture() {
  # capture URL OUT WINDOW_W WINDOW_H SCALE
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor="$5" \
    --window-size="$3,$4" \
    --virtual-time-budget="$BUDGET" \
    --user-data-dir="$TMP_DIR/profile-$RANDOM$RANDOM" \
    --screenshot="$2" \
    "$1" >/dev/null 2>&1 || true
}

shoot() {
  local name="$1" query="$2" width="$3"
  local out="$OUT_DIR/$name-$width.png"
  local url="$BASE_URL/?$query"
  local attempt
  for attempt in 1 2 3; do
    rm -f "$out"
    if [ "$width" = "390" ]; then
      local frame="$TMP_DIR/www/frame-$name.html"
      cat >"$frame" <<HTML
<!doctype html>
<html><head><meta charset="utf-8">
<style>html,body{margin:0;background:#fff}iframe{border:0;width:390px;height:844px;display:block}</style>
</head><body><iframe src="$url"></iframe></body></html>
HTML
      capture "http://127.0.0.1:$HARNESS_PORT/frame-$name.html" \
        "$TMP_DIR/raw.png" 600 844 2
      sips -c 1688 780 --cropOffset 0 0 "$TMP_DIR/raw.png" --out "$out" >/dev/null
    else
      capture "$url" "$out" "$width" 900 1
    fi
    # A blank first frame compresses to a tiny PNG. Retry those.
    if [ -f "$out" ] && [ "$(wc -c <"$out")" -gt 40000 ]; then
      break
    fi
    echo "retrying $name-$width (attempt $attempt looked blank)"
  done
  echo "wrote $out"
}

for shot in "${SHOTS[@]}"; do
  IFS='|' read -r name query widths <<<"$shot"
  for w in $widths; do
    shoot "$name" "$query" "$w"
  done
done
