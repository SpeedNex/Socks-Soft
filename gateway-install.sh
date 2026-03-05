#!/usr/bin/env bash
set -euo pipefail

GATEWAY_ID=""
SECRET=""
REDIS="127.0.0.1:6379"
INSTALL_DIR="/usr/local/bin"
BASE_URL="https://github.com/SpeedNex/Socks-Soft/raw/main/gateway"
DAEMON_MODE="false"
PID_FILE=""
LOG_FILE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-id=*) GATEWAY_ID="${1#*=}"; shift ;;
    --secret=*) SECRET="${1#*=}"; shift ;;
    --redis=*) REDIS="${1#*=}"; shift ;;
    --install-dir=*) INSTALL_DIR="${1#*=}"; shift ;;
    --gateway-id) GATEWAY_ID="${2:-}"; shift 2 ;;
    --secret) SECRET="${2:-}"; shift 2 ;;
    --redis) REDIS="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --daemon) DAEMON_MODE="true"; shift ;;
    --pid-file=*) PID_FILE="${1#*=}"; shift ;;
    --log-file=*) LOG_FILE="${1#*=}"; shift ;;
    --pid-file) PID_FILE="${2:-}"; shift 2 ;;
    --log-file) LOG_FILE="${2:-}"; shift 2 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$GATEWAY_ID" ]]; then
  echo "Missing --gateway-id"
  exit 1
fi

if [[ -z "$SECRET" ]]; then
  echo "Missing --secret"
  exit 1
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

BIN_URL="${BASE_URL}/socks-gateway-${OS}-${ARCH}"
[[ "$OS" == "windows" ]] && BIN_URL="${BIN_URL}.exe"

BIN_PATH="${INSTALL_DIR}/socks-gateway"

mkdir -p "$INSTALL_DIR"
echo "Downloading gateway from: $BIN_URL"
curl -fsSL "$BIN_URL" -o "$BIN_PATH"
chmod +x "$BIN_PATH"

echo "Starting gateway..."
RUN_ARGS=(run --gateway-id "$GATEWAY_ID" --secret "$SECRET" --redis "$REDIS")
RUN_ARGS+=("${EXTRA_ARGS[@]}")

if [[ "$DAEMON_MODE" == "true" ]]; then
  if [[ -z "$PID_FILE" ]]; then
    PID_FILE="${INSTALL_DIR}/gateway.pid"
  fi
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="${INSTALL_DIR}/gateway.log"
  fi

  mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"
  if [[ -f "$PID_FILE" ]]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
      echo "Gateway already running with PID ${OLD_PID} (pid file: ${PID_FILE})"
      exit 1
    fi
    rm -f "$PID_FILE"
  fi

  nohup "$BIN_PATH" "${RUN_ARGS[@]}" >>"$LOG_FILE" 2>&1 &
  NEW_PID=$!
  echo "$NEW_PID" >"$PID_FILE"
  echo "Gateway started in background."
  echo "PID: ${NEW_PID}"
  echo "PID file: ${PID_FILE}"
  echo "Log file: ${LOG_FILE}"
  exit 0
fi

exec "$BIN_PATH" "${RUN_ARGS[@]}"
