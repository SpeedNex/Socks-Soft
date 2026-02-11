#!/usr/bin/env bash
set -euo pipefail

TOKEN=""
AGENT_ID=""
AGENT_SECRET=""
SERVER=""
INSTALL_DIR="/usr/local/bin"
BASE_URL="https://raw.githubusercontent.com/SpeedNex/Socks-Soft/main/proxy"
DAEMON_MODE="false"
PID_FILE=""
LOG_FILE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token=*) TOKEN="${1#*=}"; shift ;;
    --agent-id=*) AGENT_ID="${1#*=}"; shift ;;
    --secret=*) AGENT_SECRET="${1#*=}"; shift ;;
    --server=*) SERVER="${1#*=}"; shift ;;
    --install-dir=*) INSTALL_DIR="${1#*=}"; shift ;;
    --base-url=*) BASE_URL="${1#*=}"; shift ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --agent-id) AGENT_ID="${2:-}"; shift 2 ;;
    --secret) AGENT_SECRET="${2:-}"; shift 2 ;;
    --server) SERVER="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
    --daemon) DAEMON_MODE="true"; shift ;;
    --pid-file=*) PID_FILE="${1#*=}"; shift ;;
    --log-file=*) LOG_FILE="${1#*=}"; shift ;;
    --pid-file) PID_FILE="${2:-}"; shift 2 ;;
    --log-file) LOG_FILE="${2:-}"; shift 2 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$AGENT_ID" && -z "$TOKEN" ]]; then
  echo "Missing --agent-id (or --token as alias)"
  exit 1
fi

if [[ -z "$AGENT_SECRET" && -z "$TOKEN" ]]; then
  echo "Missing --secret (or --token as alias)"
  exit 1
fi

if [[ -z "$SERVER" ]]; then
  echo "Missing --server"
  exit 1
fi

if [[ -z "$AGENT_ID" ]]; then
  AGENT_ID="$TOKEN"
fi
if [[ -z "$AGENT_SECRET" ]]; then
  AGENT_SECRET="$TOKEN"
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

BIN_URL="${BASE_URL}/socks-proxy-${OS}-${ARCH}"
[[ "$OS" == "windows" ]] && BIN_URL="${BIN_URL}.exe"

BIN_PATH="${INSTALL_DIR}/socks-proxy"

mkdir -p "$INSTALL_DIR"
echo "Downloading agent from: $BIN_URL"
curl -fsSL "$BIN_URL" -o "$BIN_PATH"
chmod +x "$BIN_PATH"

echo "Starting agent..."
RUN_ARGS=(run --server "$SERVER" --agent-id "$AGENT_ID" --secret "$AGENT_SECRET")
RUN_ARGS+=("${EXTRA_ARGS[@]}")

if [[ "$DAEMON_MODE" == "true" ]]; then
  if [[ -z "$PID_FILE" ]]; then
    PID_FILE="${INSTALL_DIR}/agent.pid"
  fi
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="${INSTALL_DIR}/agent.log"
  fi

  mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"
  if [[ -f "$PID_FILE" ]]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "Agent already running with PID ${OLD_PID} (pid file: ${PID_FILE})"
      exit 1
    fi
    rm -f "$PID_FILE"
  fi

  nohup "$BIN_PATH" "${RUN_ARGS[@]}" >>"$LOG_FILE" 2>&1 &
  NEW_PID=$!
  echo "$NEW_PID" >"$PID_FILE"
  echo "Agent started in background."
  echo "PID: ${NEW_PID}"
  echo "PID file: ${PID_FILE}"
  echo "Log file: ${LOG_FILE}"
  exit 0
fi

exec "$BIN_PATH" "${RUN_ARGS[@]}"
