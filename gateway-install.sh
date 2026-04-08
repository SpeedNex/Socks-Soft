#!/usr/bin/env bash
set -euo pipefail

GATEWAY_ID=""
SECRET=""
REDIS="127.0.0.1:6379"
INSTALL_DIR="/usr/local/bin"
INSTALL_DIR_EXPLICIT="false"
BASE_URL="https://github.com/SpeedNex/Socks-Soft/raw/main/gateway"
DAEMON_MODE="true"
PID_FILE=""
LOG_FILE=""
LISTEN_API=""
LISTEN_ENTRY=""
LISTEN_QUIC=""
LISTEN_SOCKS=""
ADVERTISE_QUIC_PORT=""
SERVICE_NAME=""
EXTRA_ARGS=()

COLOR_GREEN="$(printf '\033[32m')"
COLOR_RED="$(printf '\033[31m')"
COLOR_RESET="$(printf '\033[0m')"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-id=*) GATEWAY_ID="${1#*=}"; shift ;;
    --secret=*) SECRET="${1#*=}"; shift ;;
    --redis=*) REDIS="${1#*=}"; shift ;;
    --install-dir=*) INSTALL_DIR="${1#*=}"; INSTALL_DIR_EXPLICIT="true"; shift ;;
    --gateway-id) GATEWAY_ID="${2:-}"; shift 2 ;;
    --secret) SECRET="${2:-}"; shift 2 ;;
    --redis) REDIS="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; INSTALL_DIR_EXPLICIT="true"; shift 2 ;;
    --daemon) DAEMON_MODE="true"; shift ;;
    --foreground) DAEMON_MODE="false"; shift ;;
    --pid-file=*) PID_FILE="${1#*=}"; shift ;;
    --log-file=*) LOG_FILE="${1#*=}"; shift ;;
    --listen-api=*) LISTEN_API="${1#*=}"; shift ;;
    --listen-entry=*) LISTEN_ENTRY="${1#*=}"; shift ;;
    --listen-quic=*) LISTEN_QUIC="${1#*=}"; shift ;;
    --listen-socks=*) LISTEN_SOCKS="${1#*=}"; shift ;;
    --advertise-quic-port=*) ADVERTISE_QUIC_PORT="${1#*=}"; shift ;;
    --service-name=*) SERVICE_NAME="${1#*=}"; shift ;;
    --pid-file) PID_FILE="${2:-}"; shift 2 ;;
    --log-file) LOG_FILE="${2:-}"; shift 2 ;;
    --listen-api) LISTEN_API="${2:-}"; shift 2 ;;
    --listen-entry) LISTEN_ENTRY="${2:-}"; shift 2 ;;
    --listen-quic) LISTEN_QUIC="${2:-}"; shift 2 ;;
    --listen-socks) LISTEN_SOCKS="${2:-}"; shift 2 ;;
    --advertise-quic-port) ADVERTISE_QUIC_PORT="${2:-}"; shift 2 ;;
    --service-name) SERVICE_NAME="${2:-}"; shift 2 ;;
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

ensure_install_dir() {
  local target_dir="$1"
  if mkdir -p "$target_dir" 2>/dev/null && [[ -w "$target_dir" ]]; then
    return 0
  fi
  return 1
}

if ! ensure_install_dir "$INSTALL_DIR"; then
  if [[ "$INSTALL_DIR_EXPLICIT" == "true" ]]; then
    echo "Install dir is not writable: $INSTALL_DIR"
    exit 1
  fi

  FALLBACK_INSTALL_DIR="${HOME}/.local/bin"
  if ensure_install_dir "$FALLBACK_INSTALL_DIR"; then
    echo "Install dir is not writable: $INSTALL_DIR"
    echo "Falling back to: $FALLBACK_INSTALL_DIR"
    INSTALL_DIR="$FALLBACK_INSTALL_DIR"
  else
    echo "Install dir is not writable: $INSTALL_DIR"
    echo "Fallback install dir is also not writable: $FALLBACK_INSTALL_DIR"
    exit 1
  fi
fi

BIN_PATH="${INSTALL_DIR}/socks-gateway"
CONFIG_PATH="${INSTALL_DIR}/config.json"

sanitize_service_name() {
  local raw="$1"
  raw="${raw//[^a-zA-Z0-9_.@-]/-}"
  raw="${raw#-}"
  raw="${raw%-}"
  if [[ -z "$raw" ]]; then
    raw="default"
  fi
  printf '%s' "$raw"
}

ensure_service_name() {
  if [[ -n "$SERVICE_NAME" ]]; then
    SERVICE_NAME="$(sanitize_service_name "$SERVICE_NAME")"
  else
    SERVICE_NAME="socks-gateway-$(sanitize_service_name "$GATEWAY_ID")"
  fi
  if [[ "$SERVICE_NAME" != *.service ]]; then
    SERVICE_NAME="${SERVICE_NAME}.service"
  fi
}

systemd_available() {
  [[ "$OS" == "linux" ]] && command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]
}

systemd_escape_arg() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

build_execstart_line() {
  local args=("$BIN_PATH" "${RUN_ARGS[@]}")
  local parts=()
  local arg=""
  for arg in "${args[@]}"; do
    parts+=("$(systemd_escape_arg "$arg")")
  done
  local joined=""
  local part=""
  for part in "${parts[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=" "
    fi
    joined+="$part"
  done
  printf '%s' "$joined"
}

install_systemd_service() {
  ensure_service_name
  local unit_path="/etc/systemd/system/${SERVICE_NAME}"
  local work_dir
  work_dir="$(dirname "$BIN_PATH")"
  local exec_start
  exec_start="$(build_execstart_line)"
  local log_dir="${work_dir}/logs"
  local log_file="${log_dir}/proxy-gateway-$(date +%F).log"

  cat >"$unit_path" <<EOF
[Unit]
Description=Socks Gateway ${GATEWAY_ID}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${work_dir}
ExecStart=${exec_start}
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  if ! systemctl enable --now "$SERVICE_NAME"; then
    echo "Gateway installation failed: systemd service could not be started."
    echo "Service: ${SERVICE_NAME}"
    echo "Check status: systemctl status ${SERVICE_NAME}"
    echo "View logs: journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
    exit 1
  fi

  sleep 1
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "${COLOR_GREEN}Gateway installation successful.${COLOR_RESET}"
    echo "Service: ${SERVICE_NAME}"
    echo "Status: running"
    echo "Check status: systemctl status ${SERVICE_NAME}"
    echo "View journal logs: journalctl -u ${SERVICE_NAME} -f"
    echo "File logs: ${log_file}"
    return 0
  fi

  echo "Gateway installation failed: service is not running after startup."
  echo "Service: ${SERVICE_NAME}"
  echo "Check status: systemctl status ${SERVICE_NAME}"
  echo "View journal logs: journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
  echo "File logs: ${log_file}"
  exit 1
}

require_manual_stop_if_running() {
  local found_pid=""
  if [[ -n "${PID_FILE:-}" && -f "$PID_FILE" ]]; then
    local pid_from_file
    pid_from_file="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid_from_file" ]] && kill -0 "$pid_from_file" 2>/dev/null; then
      found_pid="$pid_from_file"
    fi
  fi

  if [[ -z "$found_pid" ]]; then
    found_pid="$(pgrep -f "${BIN_PATH} run" | head -n 1 || true)"
  fi

  if [[ -n "$found_pid" ]]; then
    echo "检测到网关已在运行 (PID: ${found_pid})。"
    echo "为避免重复运行/覆盖，请先手动停止网关后再执行安装脚本。"
    echo "示例: kill ${found_pid}"
    exit 1
  fi
}

require_manual_stop_if_running

extract_installed_version() {
  local bin="$1"
  if [[ ! -f "$bin" ]]; then
    return 0
  fi

  local version=""
  local build_time=""
  local go_cmd=""

  if command -v go >/dev/null 2>&1; then
    go_cmd="$(command -v go)"
  elif [[ -x "/usr/local/go/bin/go" ]]; then
    go_cmd="/usr/local/go/bin/go"
  fi

  if [[ -n "$go_cmd" ]]; then
    local meta=""
    meta="$("$go_cmd" version -m "$bin" 2>/dev/null || true)"
    if [[ -n "$meta" ]]; then
      version="$(printf '%s\n' "$meta" | sed -n 's/.*buildinfo\.Version=\([^ "]*\).*/\1/p' | head -n 1)"
      build_time="$(printf '%s\n' "$meta" | sed -n 's/.*buildinfo\.BuildTimeUTC=\([^ "]*\).*/\1/p' | head -n 1)"
      if [[ -z "$build_time" ]]; then
        build_time="$(printf '%s\n' "$meta" | awk '/vcs.time/{print $2; exit}')"
      fi
      if [[ -z "$version" ]]; then
        local rev=""
        rev="$(printf '%s\n' "$meta" | awk '/vcs.revision/{print $2; exit}')"
        if [[ -n "$rev" ]]; then
          version="rev-${rev:0:12}"
        fi
      fi
    fi
  fi

  if [[ -z "$version" ]]; then
    version="$(grep -aEo 'buildinfo\.Version=[^ "]*' "$bin" 2>/dev/null | sed 's/^buildinfo\.Version=//' | head -n 1 || true)"
  fi
  if [[ -z "$build_time" ]]; then
    build_time="$(grep -aEo 'buildinfo\.BuildTimeUTC=[^ "]*' "$bin" 2>/dev/null | sed 's/^buildinfo\.BuildTimeUTC=//' | head -n 1 || true)"
  fi
  if [[ -z "$version" ]]; then
    version="$(grep -aEo '[0-9]+\.[0-9]+\.[0-9]+\+[0-9]{14}-[0-9]+' "$bin" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$version" ]]; then
    version="$(grep -aEo '[0-9]+\.[0-9]+\.[0-9]+-dev' "$bin" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$version" ]]; then
    version="$(grep -aEo '[0-9]+\.[0-9]+\.[0-9]+' "$bin" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$build_time" ]]; then
    build_time="$(grep -aEo '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$bin" 2>/dev/null \
      | grep -v '^2006-01-02T15:04:05Z$' \
      | head -n 1 || true)"
  fi

  if [[ -n "$version" ]]; then
    echo "Installed gateway version: ${version}"
  else
    echo "Installed gateway version: unknown"
  fi
  if [[ -n "$build_time" ]]; then
    echo "Installed gateway build_time_utc: ${build_time}"
  fi
}

echo "Downloading gateway from: $BIN_URL"
curl -fsSL "$BIN_URL" -o "$BIN_PATH"
chmod +x "$BIN_PATH"
extract_installed_version "$BIN_PATH"

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
    from urllib.parse import urlparse

    value = (raw or "").strip()
    host = "127.0.0.1"
    port = 6379
    password = ""
    db = 0

    if not value:
        return host, port, password, db

    if "://" in value:
        parsed = urlparse(value)
        if parsed.hostname:
            host = parsed.hostname
        if parsed.port:
            port = parsed.port
        if parsed.password:
            password = parsed.password
        path = (parsed.path or "").strip("/")
        if path.isdigit():
            db = int(path)
        return host, port, password, db

    normalized = value
    if "@" in normalized:
        auth_part, normalized = normalized.rsplit("@", 1)
        if ":" in auth_part:
            password = auth_part.split(":", 1)[1]
        else:
            password = auth_part

    if "/" in normalized:
        normalized, db_part = normalized.split("/", 1)
        if db_part.isdigit():
            db = int(db_part)

    host, port_candidate = parse_addr(normalized)
    if host:
        host = host
    if isinstance(port_candidate, int) and port_candidate > 0:
        port = port_candidate
    return host, port, password, db

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

redis_host, redis_port, redis_password, redis_db = parse_redis(redis_raw)
cfg["redis"]["host"] = redis_host
cfg["redis"]["port"] = redis_port
cfg["redis"]["password"] = redis_password
cfg["redis"]["db"] = redis_db

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

if [[ "$DAEMON_MODE" == "true" ]]; then
  echo "Starting gateway in background..."
else
  echo "Starting gateway in foreground..."
fi
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
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  RUN_ARGS+=("${EXTRA_ARGS[@]}")
fi

if [[ "$DAEMON_MODE" == "true" ]]; then
  if systemd_available; then
    install_systemd_service
    exit 0
  fi

  if [[ -z "$PID_FILE" ]]; then
    PID_FILE="${INSTALL_DIR}/gateway.pid"
  fi
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="${INSTALL_DIR}/gateway.log"
  fi

  mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"

  echo "systemd not available; falling back to nohup background mode."
  nohup "$BIN_PATH" "${RUN_ARGS[@]}" >>"$LOG_FILE" 2>&1 &
  NEW_PID=$!
  sleep 1
  if ! kill -0 "$NEW_PID" 2>/dev/null; then
    echo "Gateway failed to stay running. Check log: ${LOG_FILE}"
    exit 1
  fi
  echo "$NEW_PID" >"$PID_FILE"
  echo "Gateway started in background."
  echo "PID: ${NEW_PID}"
  echo "PID file: ${PID_FILE}"
  echo "Log file: ${LOG_FILE}"
  exit 0
fi

exec "$BIN_PATH" "${RUN_ARGS[@]}"
