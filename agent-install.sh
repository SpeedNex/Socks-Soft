#!/usr/bin/env bash
set -euo pipefail

TOKEN=""
AGENT_ID=""
AGENT_SECRET=""
SERVER=""
INSTALL_DIR="/usr/local/bin"
BASE_URL="https://raw.githubusercontent.com/SpeedNex/Socks-Soft/main/proxy"

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
exec "$BIN_PATH" "${RUN_ARGS[@]}"
