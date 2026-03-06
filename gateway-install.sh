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
LISTEN_API=""
LISTEN_ENTRY=""
LISTEN_QUIC=""
LISTEN_SOCKS=""
ADVERTISE_QUIC_PORT=""
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
    --listen-api=*) LISTEN_API="${1#*=}"; shift ;;
    --listen-entry=*) LISTEN_ENTRY="${1#*=}"; shift ;;
    --listen-quic=*) LISTEN_QUIC="${1#*=}"; shift ;;
    --listen-socks=*) LISTEN_SOCKS="${1#*=}"; shift ;;
    --advertise-quic-port=*) ADVERTISE_QUIC_PORT="${1#*=}"; shift ;;
    --pid-file) PID_FILE="${2:-}"; shift 2 ;;
    --log-file) LOG_FILE="${2:-}"; shift 2 ;;
    --listen-api) LISTEN_API="${2:-}"; shift 2 ;;
    --listen-entry) LISTEN_ENTRY="${2:-}"; shift 2 ;;
    --listen-quic) LISTEN_QUIC="${2:-}"; shift 2 ;;
    --listen-socks) LISTEN_SOCKS="${2:-}"; shift 2 ;;
    --advertise-quic-port) ADVERTISE_QUIC_PORT="${2:-}"; shift 2 ;;
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
CONFIG_PATH="${INSTALL_DIR}/config.json"

mkdir -p "$INSTALL_DIR"
echo "Downloading gateway from: $BIN_URL"
curl -fsSL "$BIN_URL" -o "$BIN_PATH"
chmod +x "$BIN_PATH"

# Keep config.json in sync with startup parameters.
python3 - "$CONFIG_PATH" "$GATEWAY_ID" "$SECRET" "$REDIS" "$LISTEN_API" "$LISTEN_ENTRY" "$LISTEN_QUIC" "$LISTEN_SOCKS" "$ADVERTISE_QUIC_PORT" <<'PY'
import json
import os
import sys

config_path, gateway_id, secret, redis_raw, listen_api, listen_entry, listen_quic, listen_socks, adv_quic = sys.argv[1:]

def parse_addr(raw: str):
    value = (raw or "").strip()
    if not value:
        return "", None
    if value.startswith(":"):
        try:
            return "0.0.0.0", int(value[1:])
        except ValueError:
            return "0.0.0.0", None
    if ":" in value:
        host, port = value.rsplit(":", 1)
        try:
            return host.strip() or "0.0.0.0", int(port)
        except ValueError:
            return host.strip() or "0.0.0.0", None
    return value, None

def parse_redis(raw: str):
    value = (raw or "").strip()
    if "://" in value:
        value = value.split("://", 1)[1]
    host, port = parse_addr(value)
    if not host:
        host = "127.0.0.1"
    if not isinstance(port, int) or port <= 0:
        port = 6379
    return host, port

default_cfg = {
    "api": {"host": "0.0.0.0", "port": 10080},
    "quic": {"host": "0.0.0.0", "port": 10443, "cert_file": "", "key_file": ""},
    "entry": {"host": "0.0.0.0", "port": 18001},
    "socks": {"host": "0.0.0.0", "port": 13010, "allow_no_auth": False},
    "web": {
        "base_url": "https://web.example.com",
        "snapshot_path": "/api/gateway/snapshot",
        "bootstrap_path": "/api/gateway/bootstrap",
        "gateway_secret": "",
        "token": "",
        "poll_interval_seconds": 30,
        "timeout_seconds": 5,
    },
    "redis": {"host": "127.0.0.1", "port": 6379, "password": "", "db": 0, "prefix": "socks:"},
    "cluster": {
        "gateway_id": "gateway-0001",
        "advertise_host": "127.0.0.1",
        "advertise_quic_port": 10443,
        "region": "hk",
        "zone": "ap-east-1",
        "max_agents": 200,
        "agent_token_secret": "",
        "heartbeat_interval_seconds": 10,
        "ttl_seconds": 30,
    },
    "log": {
        "level": "info",
        "output": "both",
        "file_path": "logs/proxy-gateway-{date}.log",
        "max_size": 100,
        "max_backups": 7,
        "max_age": 30,
        "compress": True,
    },
}

cfg = default_cfg
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                cfg = loaded
    except Exception:
        pass

cfg.setdefault("api", {})
cfg.setdefault("quic", {})
cfg.setdefault("entry", {})
cfg.setdefault("socks", {})
cfg.setdefault("web", {})
cfg.setdefault("redis", {})
cfg.setdefault("cluster", {})

cfg["cluster"]["gateway_id"] = gateway_id
cfg["web"]["gateway_secret"] = secret

redis_host, redis_port = parse_redis(redis_raw)
cfg["redis"]["host"] = redis_host
cfg["redis"]["port"] = redis_port

api_host, api_port = parse_addr(listen_api)
if isinstance(api_port, int) and api_port > 0:
    cfg["api"]["host"] = api_host or cfg["api"].get("host", "0.0.0.0")
    cfg["api"]["port"] = api_port

entry_host, entry_port = parse_addr(listen_entry)
if isinstance(entry_port, int) and entry_port > 0:
    cfg["entry"]["host"] = entry_host or cfg["entry"].get("host", "0.0.0.0")
    cfg["entry"]["port"] = entry_port

quic_host, quic_port = parse_addr(listen_quic)
if isinstance(quic_port, int) and quic_port > 0:
    cfg["quic"]["host"] = quic_host or cfg["quic"].get("host", "0.0.0.0")
    cfg["quic"]["port"] = quic_port

socks_host, socks_port = parse_addr(listen_socks)
if isinstance(socks_port, int) and socks_port > 0:
    cfg["socks"]["host"] = socks_host or cfg["socks"].get("host", "0.0.0.0")
    cfg["socks"]["port"] = socks_port

if adv_quic.strip():
    try:
        cfg["cluster"]["advertise_quic_port"] = int(adv_quic.strip())
    except ValueError:
        pass
elif isinstance(quic_port, int) and quic_port > 0:
    cfg["cluster"]["advertise_quic_port"] = quic_port

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"Updated config: {config_path}")
PY

echo "Starting gateway..."
RUN_ARGS=(run --gateway-id "$GATEWAY_ID" --secret "$SECRET" --redis "$REDIS")
if [[ -n "$LISTEN_API" ]]; then
  RUN_ARGS+=(--listen-api "$LISTEN_API")
fi
if [[ -n "$LISTEN_ENTRY" ]]; then
  RUN_ARGS+=(--listen-entry "$LISTEN_ENTRY")
fi
if [[ -n "$LISTEN_QUIC" ]]; then
  RUN_ARGS+=(--listen-quic "$LISTEN_QUIC")
fi
if [[ -n "$LISTEN_SOCKS" ]]; then
  RUN_ARGS+=(--listen-socks "$LISTEN_SOCKS")
fi
if [[ -n "$ADVERTISE_QUIC_PORT" ]]; then
  RUN_ARGS+=(--advertise-quic-port "$ADVERTISE_QUIC_PORT")
fi
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
