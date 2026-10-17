# Shared helpers for deploy.sh and run.sh. Source it, do not run it.
#
# Settings live in .env.local next to deploy.sh (git ignored, chmod 600).
# A setting that is already saved is used as is; a missing one is asked for
# once and saved. Set RECONFIGURE=1 to be asked again with the saved values
# as defaults.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env.local"
PY="${PY:-/Library/Frameworks/Python.framework/Versions/3.12/bin/python3}"
[[ -x "$PY" ]] || PY="$(command -v python3.12 || command -v python3)"
FLUTTER="${FLUTTER:-$HOME/fvm/versions/3.47.5/bin/flutter}"
[[ -x "$FLUTTER" ]] || FLUTTER="$(command -v flutter || true)"
RECONFIGURE="${RECONFIGURE:-}"

SETTINGS=(PROJECT REGION SIARGAO_MODE GEMINI_AUTH GEMINI_MODEL GEMINI_LOCATION GOOGLE_API_KEY
  VERTEX_GRANTED DEPLOY_WEB AGENT_URL MCP_URL WEB_URL)

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

load_settings() {
  # shellcheck disable=SC1090
  [[ -f "$ENV_FILE" ]] && . "$ENV_FILE"
  return 0
}

save_settings() {
  local name
  umask 077
  {
    echo "# Siargao demo settings, written by deploy.sh / run.sh. Git ignored. Do not commit."
    for name in "${SETTINGS[@]}"; do
      printf '%s=%q\n' "$name" "${!name:-}"
    done
  } > "$ENV_FILE"
}

# needs VAR: true when VAR has no saved value (or we are reconfiguring)
needs() { [[ -z "${!1:-}" || -n "$RECONFIGURE" ]]; }

# setting VAR "Question" default
# Uses the saved value if there is one, otherwise asks and keeps the answer.
setting() {
  local name="$1" question="$2" default="$3" current="${!1:-}" reply
  needs "$name" || return 0
  read -r -p "$question [${current:-$default}]: " reply
  printf -v "$name" '%s' "${reply:-${current:-$default}}"
}

# yes_no "Question" default(y|n), returns 0 for yes
yes_no() {
  local reply
  read -r -p "$1 [$2]: " reply
  reply="${reply:-$2}"
  [[ "$reply" == [yY]* ]]
}

# Ask for everything the agent needs to reach Gemini. Used by both scripts.
ask_agent_settings() {
  if needs SIARGAO_MODE; then
    echo "Agent mode:"
    echo "  live    = demo prompts use frozen templates, free-typed prompts call Gemini"
    echo "  offline = templates only, never calls Gemini, costs nothing per request"
  fi
  setting SIARGAO_MODE "Agent mode (live/offline)" "live"
  [[ "$SIARGAO_MODE" == "live" || "$SIARGAO_MODE" == "offline" ]] || die "Mode must be live or offline."
  [[ "$SIARGAO_MODE" == "live" ]] || return 0

  if needs GEMINI_AUTH; then
    echo "Gemini access:"
    echo "  vertex = Vertex AI, billed to the project, no key needed (recommended)"
    echo "  key    = a Gemini API key from https://aistudio.google.com/apikey"
  fi
  setting GEMINI_AUTH "Gemini access (vertex/key)" "vertex"
  case "$GEMINI_AUTH" in
    key)
      if needs GOOGLE_API_KEY; then
        local key
        read -r -s -p "Paste your Gemini API key (hidden, Enter keeps the saved one): " key; echo
        GOOGLE_API_KEY="${key:-${GOOGLE_API_KEY:-}}"
      fi
      [[ -n "${GOOGLE_API_KEY:-}" ]] || die "No Gemini API key entered."
      ;;
    vertex)
      GOOGLE_API_KEY=""
      setting GEMINI_LOCATION "Vertex AI location for the model" "global"
      ;;
    *) die "Gemini access must be vertex or key." ;;
  esac
  setting GEMINI_MODEL "Gemini model" "gemini-3.5-flash"
}

ensure_gcloud_login() {
  command -v gcloud >/dev/null || die "gcloud is not installed. Install the Google Cloud SDK first."
  ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
  if [[ -z "$ACCOUNT" ]]; then
    echo "You are not logged in to gcloud. Opening the browser login."
    gcloud auth login
    ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
  fi
  echo "gcloud account: $ACCOUNT"
}

ensure_venv() {
  local svc="$1"
  [[ -x "$ROOT/$svc/.venv/bin/python" ]] && return 0
  echo "Setting up $svc/.venv (one time)"
  (cd "$ROOT/$svc" && "$PY" -m venv .venv)
  if [[ -f "$ROOT/$svc/constraints.txt" ]]; then
    (cd "$ROOT/$svc" && .venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt -c constraints.txt)
  else
    (cd "$ROOT/$svc" && .venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt)
  fi
}
