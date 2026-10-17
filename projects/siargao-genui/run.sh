#!/usr/bin/env bash
# One command to try the demo.
#
#   ./run.sh               app on the iOS Simulator, talking to Cloud Run
#                          (deploys first if the services are not there yet)
#   ./run.sh --redeploy    deploy again first (after changing agent or MCP code)
#   ./run.sh --local       run the agent and MCP server on this Mac instead, no cloud
#   ./run.sh --offline     app only, recorded fixtures, no servers at all
#   ./run.sh --chrome      use Chrome instead of the simulator (combine with any of the above)
#   ./run.sh --setup       change saved settings (project, mode, Gemini key...)
#   ./run.sh -- ARGS       pass ARGS to flutter run, for example
#                          ./run.sh --local -- --dart-define=DEEP_LINK=tab=home
#
# Settings are asked once and saved in .env.local (git ignored).
set -euo pipefail
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"

TARGET=cloud
DEVICE=ios
REDEPLOY=""
FLUTTER_ARGS=()
while [[ $# -gt 0 ]]; do
  arg="$1"; shift
  case "$arg" in
    --) FLUTTER_ARGS=("$@"); break ;;
    --redeploy) REDEPLOY=1 ;;
    --local) TARGET=local ;;
    --offline) TARGET=offline ;;
    --chrome) DEVICE=chrome ;;
    --setup) RECONFIGURE=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) die "Unknown option $arg. Try ./run.sh --help" ;;
  esac
done
[[ -x "$FLUTTER" ]] || die "Flutter not found. Install it or set FLUTTER=/path/to/flutter."
load_settings

service_exists() {
  gcloud run services describe "$1" --project "$PROJECT" --region "$REGION" \
    --format 'value(status.url)' 2>/dev/null
}

# Start a server in the background and wait for it to answer.
start_local() {
  local name="$1" dir="$2" port="$3" url="$4" pid holder
  shift 4
  holder="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)"
  if [[ -n "$holder" ]]; then
    die "Port $port is already in use by: $(ps -o command= -p "$holder"). Stop it (kill $holder) and run again."
  fi
  mkdir -p "$ROOT/.run"
  (cd "$ROOT/$dir" && exec env "$@" .venv/bin/python -m "$name" > "$ROOT/.run/$name.log" 2>&1) &
  pid="$!"
  PIDS+=("$pid")
  for _ in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || die "$name stopped while starting. See .run/$name.log"
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
      echo "  $name is up ($url), log in .run/$name.log"
      return 0
    fi
    sleep 0.25
  done
  die "$name did not answer on $url. See .run/$name.log"
}

PIDS=()
cleanup() { [[ ${#PIDS[@]} -gt 0 ]] && kill "${PIDS[@]}" 2>/dev/null; return 0; }
trap cleanup EXIT

DEFINES=()
case "$TARGET" in
  cloud)
    ensure_gcloud_login
    if [[ -z "${PROJECT:-}" || -z "${REGION:-}" || -n "$RECONFIGURE" ]]; then
      setting PROJECT "Google Cloud project" "$(gcloud config get-value project 2>/dev/null || echo devfest-genui-manila)"
      setting REGION "Cloud Run region" "asia-southeast1"
      save_settings
    fi
    if [[ -n "$REDEPLOY" || -n "$RECONFIGURE" ]]; then
      say "Deploying"
      "$ROOT/deploy.sh" $( [[ -n "$RECONFIGURE" ]] && echo --reconfigure )
    else
      say "Checking Cloud Run services in $PROJECT/$REGION"
      agent_url="$(service_exists siargao-agent || true)"
      mcp_url="$(service_exists siargao-mcp || true)"
      if [[ -z "$agent_url" || -z "$mcp_url" ]]; then
        echo "siargao-agent or siargao-mcp is not deployed yet."
        "$ROOT/deploy.sh"
      else
        AGENT_URL="$agent_url"; MCP_URL="$mcp_url/mcp"; save_settings
        echo "  agent  $AGENT_URL"
        echo "  mcp    $MCP_URL"
      fi
    fi
    load_settings
    DEFINES=(--dart-define=DEMO_MODE=live --dart-define=AGENT_URL="$AGENT_URL" --dart-define=MCP_URL="$MCP_URL")
    ;;
  local)
    say "Starting the agent and MCP server on this Mac"
    ask_agent_settings
    save_settings
    ensure_venv agent
    ensure_venv mcp
    AGENT_ENV=(SIARGAO_MODE="$SIARGAO_MODE" GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.5-flash}")
    if [[ "$SIARGAO_MODE" == live && "$GEMINI_AUTH" == key ]]; then
      AGENT_ENV+=(GOOGLE_GENAI_USE_VERTEXAI=FALSE GOOGLE_API_KEY="$GOOGLE_API_KEY")
    elif [[ "$SIARGAO_MODE" == live ]]; then
      ensure_gcloud_login
      gcloud auth application-default print-access-token >/dev/null 2>&1 \
        || { echo "Vertex AI needs Application Default Credentials. Opening the browser login."; gcloud auth application-default login; }
      AGENT_ENV+=(GOOGLE_GENAI_USE_VERTEXAI=TRUE GOOGLE_CLOUD_PROJECT="${PROJECT:-devfest-genui-manila}"
        GOOGLE_CLOUD_LOCATION="${GEMINI_LOCATION:-global}")
    fi
    start_local siargao_agent agent 10002 http://localhost:10002/.well-known/agent-card.json "${AGENT_ENV[@]}"
    start_local siargao_mcp mcp 10003 http://localhost:10003/mcp LOG_LEVEL=INFO
    DEFINES=(--dart-define=DEMO_MODE=live --dart-define=AGENT_URL=http://localhost:10002
      --dart-define=MCP_URL=http://localhost:10003/mcp)
    ;;
  offline)
    DEFINES=(--dart-define=DEMO_MODE=offline)
    ;;
esac

if [[ "$DEVICE" == ios ]]; then
  say "Starting the iOS Simulator"
  command -v xcrun >/dev/null || die "Xcode is not installed. Use ./run.sh --chrome instead."
  DEVICE_ID="$(xcrun simctl list devices booted | grep -E 'iPhone|iPad' | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
  if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID="$(xcrun simctl list devices available | grep -E '^ +iPhone 1[0-9]( Pro)? \(' | tail -1 | grep -oE '[0-9A-F-]{36}' || true)"
    [[ -n "$DEVICE_ID" ]] || DEVICE_ID="$(xcrun simctl list devices available | grep iPhone | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
    [[ -n "$DEVICE_ID" ]] || die "No iPhone simulator found. Add one in Xcode > Window > Devices and Simulators."
    xcrun simctl boot "$DEVICE_ID"
  fi
  open -a Simulator
  echo "  simulator $DEVICE_ID"
else
  DEVICE_ID=chrome
fi

say "Running the app ($TARGET). Press r to hot reload, q to quit."
cd "$ROOT/app"
"$FLUTTER" run -d "$DEVICE_ID" "${DEFINES[@]}" ${FLUTTER_ARGS[@]+"${FLUTTER_ARGS[@]}"}
