#!/usr/bin/env bash
# Copy the shared catalog files (and the stays dataset) into the agent package.
#
# The agent vendors these files so its Docker build context stays inside
# agent/. tests/test_vendored.py fails if the copies drift from the source, so
# run this after any change in ../catalog or ../fixtures/stays_dataset.json.
#
# Usage (from anywhere): agent/scripts/sync_catalog.sh
set -euo pipefail

AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${AGENT_DIR}/.." && pwd)"
DEST="${AGENT_DIR}/siargao_agent/catalog"

mkdir -p "${DEST}"
for f in siargao_catalog.json rules.txt images.json; do
  cp "${PROJECT_DIR}/catalog/${f}" "${DEST}/${f}"
  echo "synced catalog/${f}"
done
cp "${PROJECT_DIR}/fixtures/stays_dataset.json" "${AGENT_DIR}/data/stays_dataset.json"
echo "synced fixtures/stays_dataset.json"
