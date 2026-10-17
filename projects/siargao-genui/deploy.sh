#!/usr/bin/env bash
# Set up and deploy the Siargao demo to Cloud Run.
#
#   ./deploy.sh                 asks only for settings not saved yet, then deploys
#   ./deploy.sh --reconfigure   asks every question again
#   DRY_RUN=1 ./deploy.sh       prints what it would run, changes nothing
#
# Answers are saved in .env.local (git ignored). Deploys siargao-agent and
# siargao-mcp, smoke tests both, and can also deploy the web app
# (siargao-web). Nothing is deployed until you type "deploy" at the summary.
# You normally do not run this directly: ./run.sh calls it when needed.
set -euo pipefail
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"

[[ "${1:-}" == "--reconfigure" ]] && RECONFIGURE=1
DRY_RUN="${DRY_RUN:-}"

# run a command, or just print it in dry run mode
run() {
  if [[ -n "$DRY_RUN" ]]; then
    echo "  (dry run) $*"
  else
    "$@"
  fi
}

service_url() {
  if [[ -n "$DRY_RUN" ]]; then
    echo "https://$1-dryrun.a.run.app"
  else
    gcloud run services describe "$1" --project "$PROJECT" --region "$REGION" --format 'value(status.url)'
  fi
}

say "Siargao demo: deploy to Cloud Run"
[[ -n "$DRY_RUN" ]] && echo "DRY RUN: nothing will be created or changed."
load_settings

say "1/5 Google Cloud login"
ensure_gcloud_login

say "2/5 Settings"
setting PROJECT "Google Cloud project" "$(gcloud config get-value project 2>/dev/null || echo devfest-genui-manila)"
setting REGION "Cloud Run region" "asia-southeast1"
gcloud projects describe "$PROJECT" --format='value(projectId)' >/dev/null 2>&1 \
  || die "Cannot read project $PROJECT with $ACCOUNT. Check the project ID and your access."
ask_agent_settings

GRANT_VERTEX="n"
if [[ "$SIARGAO_MODE" == "live" && "$GEMINI_AUTH" == "vertex" && "${VERTEX_GRANTED:-}" != "yes" ]]; then
  if yes_no "Grant roles/aiplatform.user to the Cloud Run service account so it can call Gemini? (needed once)" y; then
    GRANT_VERTEX="y"
  fi
fi

if [[ -z "${DEPLOY_WEB:-}" || -n "$RECONFIGURE" ]]; then
  if yes_no "Also deploy the Flutter web app to Cloud Run (siargao-web)?" n; then DEPLOY_WEB=yes; else DEPLOY_WEB=no; fi
fi
if [[ "$DEPLOY_WEB" == yes && ! -x "$FLUTTER" ]]; then
  die "Flutter not found. Set FLUTTER=/path/to/flutter."
fi
save_settings

say "3/5 Summary"
cat <<EOF
  Account        $ACCOUNT
  Project        $PROJECT
  Region         $REGION
  Agent          siargao-agent, mode=$SIARGAO_MODE$( [[ "$SIARGAO_MODE" == live ]] && echo ", $GEMINI_MODEL via $GEMINI_AUTH" )
  MCP server     siargao-mcp
  Web app        $( [[ "$DEPLOY_WEB" == yes ]] && echo "siargao-web" || echo "skip" )
  IAM grant      $( [[ "$GRANT_VERTEX" == y ]] && echo "roles/aiplatform.user on the default compute service account" || echo "none" )

  All services are public (--allow-unauthenticated, max 3 instances).
  In live mode anyone with the agent URL can trigger Gemini calls on your bill.
  Settings are saved in .env.local. Change them with ./run.sh --setup
EOF
if [[ "$SIARGAO_MODE" == live && "$GEMINI_AUTH" == key ]]; then
  echo "  The API key is set as a plain env var on the Cloud Run service (visible to project viewers)."
fi
echo
read -r -p "Type deploy to continue, anything else to stop: " CONFIRM
[[ "$CONFIRM" == "deploy" ]] || die "Stopped. Nothing was deployed."

export PROJECT REGION CONFIRM_DEPLOY=yes

say "4/5 Local checks"
for svc in agent mcp; do
  ensure_venv "$svc"
  (cd "$ROOT/$svc" && .venv/bin/pytest -q) || die "$svc tests failed. Fix them before deploying."
done

say "5/5 Deploy"
run gcloud config set project "$PROJECT" >/dev/null

if [[ "$GRANT_VERTEX" == y ]]; then
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
  echo "Granting roles/aiplatform.user to ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
  run gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/aiplatform.user" --condition=None --quiet >/dev/null
  if [[ -z "$DRY_RUN" ]]; then VERTEX_GRANTED=yes; save_settings; fi
fi

echo
echo "Deploying the agent. The first deploy may ask to create an Artifact Registry repository: answer Y."
(cd "$ROOT/agent" && SIARGAO_MODE="$SIARGAO_MODE" GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.5-flash}" \
  GEMINI_LOCATION="${GEMINI_LOCATION:-global}" GOOGLE_API_KEY="${GOOGLE_API_KEY:-}" run ./deploy.sh)
AGENT_URL="$(service_url siargao-agent)"
run "$ROOT/agent/.venv/bin/python" "$ROOT/agent/scripts/smoke.py" "$AGENT_URL"

echo
echo "Deploying the MCP server."
(cd "$ROOT/mcp" && run ./deploy.sh)
MCP_URL="$(service_url siargao-mcp)/mcp"
run "$ROOT/mcp/.venv/bin/python" "$ROOT/mcp/scripts/smoke.py" "${MCP_URL%/mcp}"

if [[ "$DEPLOY_WEB" == yes ]]; then
  echo
  echo "Building and deploying the web app."
  (cd "$ROOT/app/web_deploy" && AGENT_URL="$AGENT_URL" MCP_URL="$MCP_URL" FLUTTER="$FLUTTER" run ./deploy.sh)
  WEB_URL="$(service_url siargao-web)"
fi
if [[ -z "$DRY_RUN" ]]; then save_settings; fi

say "Deployed"
echo "  Agent       $AGENT_URL"
echo "  MCP         $MCP_URL"
if [[ "$DEPLOY_WEB" == yes ]]; then echo "  Web app     ${WEB_URL:-}"; fi
cat <<EOF

Run the app on the simulator against these:  ./run.sh
Tear down after the talk:
  for s in siargao-agent siargao-mcp siargao-web; do gcloud run services delete \$s --region $REGION --project $PROJECT --quiet; done
EOF
