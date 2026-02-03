#!/usr/bin/env bash
set -euo pipefail

GATEWAY_ID=""
SECRET=""
REDIS="127.0.0.1:6379"
INSTALL_DIR="/usr/local/bin"
BASE_URL="https://github.com/SpeedNex/Socks-Soft/raw/main/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-id=*) GATEWAY_ID="${1#*=}"; shift ;;
    --secret=*) SECRET="${1#*=}"; shift ;;
    --redis=*) REDIS="${1#*=}"; shift ;;
    --install-dir=*) INSTALL_DIR="${1#*=}"; shift ;;
    --base-url=*) BASE_URL="${1#*=}"; shift ;;
    --gateway-id) GATEWAY_ID="${2:-}"; shift 2 ;;
    --secret) SECRET="${2:-}"; shift 2 ;;
    --redis) REDIS="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
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
exec "$BIN_PATH" run --gateway-id "$GATEWAY_ID" --secret "$SECRET" --redis "$REDIS"
