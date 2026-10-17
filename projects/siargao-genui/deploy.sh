#!/usr/bin/env bash
# One-stop setup and deploy for the Siargao demo on Cloud Run.
#
#   ./deploy.sh            asks a few questions, shows a summary, then deploys
#   DRY_RUN=1 ./deploy.sh  same questions, prints what it would run, changes nothing
#
# It deploys siargao-agent and siargao-mcp, smoke tests both, and can also
# build and deploy the Flutter web app (siargao-web). Nothing is deployed
# until you type "deploy" at the summary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PY:-/Library/Frameworks/Python.framework/Versions/3.12/bin/python3}"
FLUTTER="${FLUTTER:-$HOME/fvm/versions/3.47.5/bin/flutter}"
DRY_RUN="${DRY_RUN:-}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ask VAR "Question" default
ask() {
  local reply
  read -r -p "$2 [$3]: " reply
  printf -v "$1" '%s' "${reply:-$3}"
}

# yes_no "Question" default(y|n), returns 0 for yes
yes_no() {
  local reply
  read -r -p "$1 [$2]: " reply
  reply="${reply:-$2}"
  [[ "$reply" == [yY]* ]]
}

# run a command, or just print it in dry run mode
run() {
  if [[ -n "$DRY_RUN" ]]; then
    echo "  (dry run) $*"
  else
    "$@"
  fi
}

say "Siargao demo: deploy to Cloud Run"
[[ -n "$DRY_RUN" ]] && echo "DRY RUN: nothing will be created or changed."

# 1. Tools
command -v gcloud >/dev/null || die "gcloud is not installed. Install the Google Cloud SDK first."
[[ -x "$PY" ]] || PY="$(command -v python3.12 || command -v python3)" || die "Python 3.12 not found."

# 2. Google Cloud login
say "1/5 Google Cloud login"
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
if [[ -z "$ACCOUNT" ]]; then
  echo "You are not logged in to gcloud. Opening the browser login."
  gcloud auth login
  ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
fi
echo "Logged in as $ACCOUNT"
yes_no "Use this account?" y || { gcloud auth login; ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"; }

# 3. Settings
say "2/5 Settings (press Enter to keep the default)"
ask PROJECT "Google Cloud project" "$(gcloud config get-value project 2>/dev/null || echo devfest-genui-manila)"
ask REGION "Cloud Run region" "asia-southeast1"
gcloud projects describe "$PROJECT" --format='value(projectId)' >/dev/null 2>&1 \
  || die "Cannot read project $PROJECT with $ACCOUNT. Check the project ID and your access."

echo
echo "Agent mode:"
echo "  live    = demo prompts use frozen templates, free-typed prompts call Gemini"
echo "  offline = templates only, never calls Gemini, costs nothing per request"
ask SIARGAO_MODE "Agent mode (live/offline)" "live"
[[ "$SIARGAO_MODE" == "live" || "$SIARGAO_MODE" == "offline" ]] || die "Mode must be live or offline."

GOOGLE_API_KEY=""
GEMINI_AUTH="vertex"
GEMINI_MODEL="gemini-3.5-flash"
GEMINI_LOCATION="global"
GRANT_VERTEX="n"
if [[ "$SIARGAO_MODE" == "live" ]]; then
  echo
  echo "Gemini access:"
  echo "  vertex = Vertex AI, billed to $PROJECT, no key needed (recommended)"
  echo "  key    = a Gemini API key from https://aistudio.google.com/apikey"
  ask GEMINI_AUTH "Gemini access (vertex/key)" "vertex"
  case "$GEMINI_AUTH" in
    key)
      read -r -s -p "Paste your Gemini API key (hidden): " GOOGLE_API_KEY; echo
      [[ -n "$GOOGLE_API_KEY" ]] || die "No key entered."
      ;;
    vertex)
      ask GEMINI_LOCATION "Vertex AI location for the model" "global"
      if yes_no "Grant roles/aiplatform.user to the Cloud Run service account so it can call Gemini? (needed once)" y; then
        GRANT_VERTEX="y"
      fi
      ;;
    *) die "Gemini access must be vertex or key." ;;
  esac
  ask GEMINI_MODEL "Gemini model" "gemini-3.5-flash"
fi

echo
DEPLOY_WEB="n"
if yes_no "Also build and deploy the Flutter web app (siargao-web)?" y; then
  [[ -x "$FLUTTER" ]] || die "Flutter not found at $FLUTTER. Set FLUTTER=/path/to/flutter."
  DEPLOY_WEB="y"
fi

# 4. Summary and confirmation
say "3/5 Summary"
cat <<EOF
  Account        $ACCOUNT
  Project        $PROJECT
  Region         $REGION
  Agent          siargao-agent, mode=$SIARGAO_MODE$( [[ "$SIARGAO_MODE" == live ]] && echo ", $GEMINI_MODEL via $GEMINI_AUTH" )
  MCP server     siargao-mcp
  Web app        $( [[ "$DEPLOY_WEB" == y ]] && echo "siargao-web" || echo "skip (run it locally instead)" )
  IAM grant      $( [[ "$GRANT_VERTEX" == y ]] && echo "roles/aiplatform.user on the default compute service account" || echo "none" )

  All services are public (--allow-unauthenticated, max 3 instances).
  In live mode anyone with the agent URL can trigger Gemini calls on your bill.
EOF
[[ "$GEMINI_AUTH" == key ]] && echo "  The API key is stored as a plain env var on the Cloud Run service (visible to project viewers)."
echo
read -r -p "Type deploy to continue, anything else to stop: " CONFIRM
[[ "$CONFIRM" == "deploy" ]] || die "Stopped. Nothing was changed."

export PROJECT REGION CONFIRM_DEPLOY=yes

# 5. Local checks
say "4/5 Local checks"
for svc in agent mcp; do
  if [[ ! -x "$ROOT/$svc/.venv/bin/python" ]]; then
    echo "Setting up $svc/.venv"
    (cd "$ROOT/$svc" && "$PY" -m venv .venv)
    if [[ -f "$ROOT/$svc/constraints.txt" ]]; then
      (cd "$ROOT/$svc" && .venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt -c constraints.txt)
    else
      (cd "$ROOT/$svc" && .venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt)
    fi
  fi
  (cd "$ROOT/$svc" && .venv/bin/pytest -q) || die "$svc tests failed. Fix them before deploying."
done

# 6. Deploy
say "5/5 Deploy"
run gcloud config set project "$PROJECT" >/dev/null

if [[ "$GRANT_VERTEX" == y ]]; then
  PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
  echo "Granting roles/aiplatform.user to ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
  run gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
    --role="roles/aiplatform.user" --condition=None --quiet >/dev/null
fi

service_url() {
  if [[ -n "$DRY_RUN" ]]; then
    echo "https://$1-dryrun.a.run.app"
  else
    gcloud run services describe "$1" --project "$PROJECT" --region "$REGION" --format 'value(status.url)'
  fi
}

echo
echo "Deploying the agent. The first deploy may ask to create an Artifact Registry repository: answer Y."
(cd "$ROOT/agent" && SIARGAO_MODE="$SIARGAO_MODE" GEMINI_MODEL="$GEMINI_MODEL" \
  GEMINI_LOCATION="$GEMINI_LOCATION" GOOGLE_API_KEY="$GOOGLE_API_KEY" run ./deploy.sh)
AGENT_URL="$(service_url siargao-agent)"
run "$ROOT/agent/.venv/bin/python" "$ROOT/agent/scripts/smoke.py" "$AGENT_URL"

echo
echo "Deploying the MCP server."
(cd "$ROOT/mcp" && run ./deploy.sh)
MCP_BASE="$(service_url siargao-mcp)"
run "$ROOT/mcp/.venv/bin/python" "$ROOT/mcp/scripts/smoke.py" "$MCP_BASE"

WEB_URL=""
if [[ "$DEPLOY_WEB" == y ]]; then
  echo
  echo "Building and deploying the web app."
  (cd "$ROOT/app/web_deploy" && AGENT_URL="$AGENT_URL" MCP_URL="$MCP_BASE/mcp" FLUTTER="$FLUTTER" run ./deploy.sh)
  WEB_URL="$(service_url siargao-web)"
fi

say "Done"
echo "  Agent       $AGENT_URL  (card: $AGENT_URL/.well-known/agent-card.json)"
echo "  MCP         $MCP_BASE/mcp"
[[ -n "$WEB_URL" ]] && echo "  Web app     $WEB_URL"
cat <<EOF

Run the app locally against these services:
  cd app && $FLUTTER run -d chrome --dart-define=DEMO_MODE=live \\
    --dart-define=AGENT_URL=$AGENT_URL --dart-define=MCP_URL=$MCP_BASE/mcp

Tear down after the talk:
  for s in siargao-agent siargao-mcp siargao-web; do gcloud run services delete \$s --region $REGION --project $PROJECT --quiet; done
EOF
