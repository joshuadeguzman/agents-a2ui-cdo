#!/usr/bin/env bash
# Deploy the Siargao MCP server to Cloud Run from source.
#
# This creates or updates a cloud resource, so it refuses to run unless you
# opt in explicitly:
#
#   CONFIRM_DEPLOY=yes ./deploy.sh
#
# Override PROJECT, REGION or SERVICE with environment variables if needed.
set -euo pipefail

PROJECT="${PROJECT:-devfest-genui-manila}"
REGION="${REGION:-asia-southeast1}"
SERVICE="${SERVICE:-siargao-mcp}"

if [[ "${CONFIRM_DEPLOY:-}" != "yes" ]]; then
  echo "Refusing to deploy. This runs 'gcloud run deploy ${SERVICE} --source .' in ${PROJECT} (${REGION})." >&2
  echo "Run it as: CONFIRM_DEPLOY=yes ./deploy.sh" >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")"

# Make sure the vendored fixtures and catalog are current before uploading.
./scripts/sync_shared.sh

gcloud run deploy "${SERVICE}" \
  --project "${PROJECT}" \
  --region "${REGION}" \
  --source . \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 3 \
  --set-env-vars LOG_LEVEL=INFO

URL="$(gcloud run services describe "${SERVICE}" --project "${PROJECT}" --region "${REGION}" --format 'value(status.url)')"
echo "Deployed: ${URL}/mcp"
echo "Smoke test: .venv/bin/python scripts/smoke.py ${URL}"
