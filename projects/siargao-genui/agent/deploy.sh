#!/usr/bin/env bash
# Deploy the Siargao agent to Cloud Run from source (Cloud Build builds the
# Dockerfile in this folder).
#
# This creates or updates a cloud resource, so it refuses to run unless you
# set CONFIRM_DEPLOY=yes:
#
#   CONFIRM_DEPLOY=yes ./deploy.sh
#
# Overridable: PROJECT, REGION, SERVICE, GEMINI_MODEL, GEMINI_LOCATION,
# SIARGAO_MODE, SIARGAO_MODEL_RETRY.
set -euo pipefail

if [[ "${CONFIRM_DEPLOY:-}" != "yes" ]]; then
  echo "Refusing to deploy. Re-run with CONFIRM_DEPLOY=yes ./deploy.sh" >&2
  exit 1
fi

PROJECT="${PROJECT:-devfest-genui-manila}"
REGION="${REGION:-asia-southeast1}"
SERVICE="${SERVICE:-siargao-agent}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.5-flash}"
# Vertex AI location for the model call, separate from the Cloud Run region.
# Newer Gemini models are served from the global endpoint.
GEMINI_LOCATION="${GEMINI_LOCATION:-global}"
SIARGAO_MODE="${SIARGAO_MODE:-live}"
SIARGAO_MODEL_RETRY="${SIARGAO_MODEL_RETRY:-false}"

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Deploying ${SERVICE} to ${PROJECT}/${REGION} (mode=${SIARGAO_MODE}, model=${GEMINI_MODEL}@${GEMINI_LOCATION})"
gcloud run deploy "${SERVICE}" \
  --project "${PROJECT}" \
  --region "${REGION}" \
  --source . \
  --allow-unauthenticated \
  --port 8080 \
  --memory 1Gi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 3 \
  --timeout 120 \
  --set-env-vars "SIARGAO_MODE=${SIARGAO_MODE},GOOGLE_GENAI_USE_VERTEXAI=TRUE,GOOGLE_CLOUD_PROJECT=${PROJECT},GOOGLE_CLOUD_LOCATION=${GEMINI_LOCATION},GEMINI_MODEL=${GEMINI_MODEL},SIARGAO_MODEL_RETRY=${SIARGAO_MODEL_RETRY}"

URL="$(gcloud run services describe "${SERVICE}" --project "${PROJECT}" --region "${REGION}" --format 'value(status.url)')"
echo "Deployed: ${URL}"
echo "Agent card: ${URL}/.well-known/agent-card.json"
echo "Smoke test: .venv/bin/python scripts/smoke.py ${URL}"
