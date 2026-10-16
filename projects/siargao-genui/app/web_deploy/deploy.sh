#!/usr/bin/env bash
# Build the Flutter web app in live mode and deploy it to Cloud Run as a static site.
#
# Needs the deployed agent and MCP URLs:
#   CONFIRM_DEPLOY=yes AGENT_URL=https://siargao-agent-xxxx.run.app \
#     MCP_URL=https://siargao-mcp-xxxx.run.app/mcp ./deploy.sh
set -euo pipefail

if [[ "${CONFIRM_DEPLOY:-}" != "yes" ]]; then
  echo "Refusing to deploy. Run it as: CONFIRM_DEPLOY=yes AGENT_URL=... MCP_URL=... ./deploy.sh" >&2
  exit 1
fi
: "${AGENT_URL:?Set AGENT_URL to the deployed agent URL}"
: "${MCP_URL:?Set MCP_URL to the deployed MCP URL, ending in /mcp}"

PROJECT="${PROJECT:-devfest-genui-manila}"
REGION="${REGION:-asia-southeast1}"
SERVICE="${SERVICE:-siargao-web}"
FLUTTER="${FLUTTER:-$HOME/fvm/versions/3.47.5/bin/flutter}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${HERE}/.."
"${FLUTTER}" build web --release --no-web-resources-cdn \
  --dart-define=DEMO_MODE=live \
  --dart-define=AGENT_URL="${AGENT_URL}" \
  --dart-define=MCP_URL="${MCP_URL}"

rm -rf "${HERE}/site"
cp -R build/web "${HERE}/site"

cd "${HERE}"
gcloud run deploy "${SERVICE}" \
  --project "${PROJECT}" \
  --region "${REGION}" \
  --source . \
  --allow-unauthenticated \
  --memory 256Mi \
  --max-instances 2

echo "Deployed: $(gcloud run services describe "${SERVICE}" --project "${PROJECT}" --region "${REGION}" --format 'value(status.url)')"
