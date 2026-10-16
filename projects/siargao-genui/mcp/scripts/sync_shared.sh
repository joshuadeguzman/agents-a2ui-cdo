#!/usr/bin/env bash
# Copy the shared fixtures and catalog into mcp/ so the Docker build context
# (which is mcp/ only) has everything the server needs.
#
# Run from anywhere: mcp/scripts/sync_shared.sh
# tests/test_vendored.py fails if these copies drift from their sources.
set -euo pipefail

MCP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(cd "$MCP_DIR/.." && pwd)"

copy() {
  mkdir -p "$(dirname "$MCP_DIR/$2")"
  cp "$SRC/$1" "$MCP_DIR/$2"
  echo "copied $1 -> mcp/$2"
}

copy fixtures/home_first_run.json surfaces/home_first_run.json
copy fixtures/stays_dataset.json data/stays.json
copy catalog/siargao_catalog.json catalog/siargao_catalog.json
copy catalog/images.json catalog/images.json
copy catalog/spec/v0_9/server_to_client.json catalog/spec/v0_9/server_to_client.json
copy catalog/spec/v0_9/common_types.json catalog/spec/v0_9/common_types.json
copy catalog/spec/v0_9/SOURCE.txt catalog/spec/v0_9/SOURCE.txt
