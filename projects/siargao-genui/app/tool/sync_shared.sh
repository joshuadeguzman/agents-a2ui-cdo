#!/usr/bin/env bash
# Copies the shared fixtures and image list into the app assets.
# Run from anywhere: tool/sync_shared.sh
# test/shared_sync_test.dart fails when the copies drift from the sources.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$APP_DIR/.." && pwd)"

mkdir -p "$APP_DIR/assets/fixtures" "$APP_DIR/assets/catalog"
rm -f "$APP_DIR"/assets/fixtures/*.json
cp "$ROOT_DIR"/fixtures/*.json "$APP_DIR/assets/fixtures/"
cp "$ROOT_DIR/catalog/images.json" "$APP_DIR/assets/catalog/images.json"

count="$(find "$APP_DIR/assets/fixtures" -name '*.json' | wc -l | tr -d ' ')"
echo "Synced $count fixtures and images.json"
