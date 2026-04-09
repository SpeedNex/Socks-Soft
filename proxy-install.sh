#!/usr/bin/env bash
set -euo pipefail

TOKEN=""
AGENT_ID=""
AGENT_SECRET=""
SERVER=""
INSTALL_DIR="/usr/local/bin"
BASE_URL="https://raw.githubusercontent.com/SpeedNex/Socks-Soft/main/proxy"
DAEMON_MODE="true"
PID_FILE=""
LOG_FILE=""
SERVICE_NAME=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token=*) TOKEN="${1#*=}"; shift ;;
    --agent-id=*) AGENT_ID="${1#*=}"; shift ;;
    --secret=*) AGENT_SECRET="${1#*=}"; shift ;;
    --web-server-url=*) SERVER="${1#*=}"; shift ;;
    --base-url=*) BASE_URL="${1#*=}"; shift ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --agent-id) AGENT_ID="${2:-}"; shift 2 ;;
    --secret) AGENT_SECRET="${2:-}"; shift 2 ;;
    --web-server-url) SERVER="${2:-}"; shift 2 ;;
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
    --daemon) DAEMON_MODE="true"; shift ;;
    --foreground) DAEMON_MODE="false"; shift ;;
    --pid-file=*) PID_FILE="${1#*=}"; shift ;;
    --log-file=*) LOG_FILE="${1#*=}"; shift ;;
    --service-name=*) SERVICE_NAME="${1#*=}"; shift ;;
    --pid-file) PID_FILE="${2:-}"; shift 2 ;;
    --log-file) LOG_FILE="${2:-}"; shift 2 ;;
    --service-name) SERVICE_NAME="${2:-}"; shift 2 ;;
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
  echo "Missing --web-server-url"
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

if ! mkdir -p "$INSTALL_DIR" 2>/dev/null || [[ ! -w "$INSTALL_DIR" ]]; then
  INSTALL_DIR="${HOME}/.local/bin"
  mkdir -p "$INSTALL_DIR"
  echo "No write permission for /usr/local/bin, using ${INSTALL_DIR}"
fi

BIN_PATH="${INSTALL_DIR}/socks-proxy"
CONFIG_PATH="${INSTALL_DIR}/agent.config.json"

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
    SERVICE_NAME="socks-proxy-$(sanitize_service_name "$AGENT_ID")"
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
  local log_file="${work_dir}/agent.log"

  cat >"$unit_path" <<EOF
[Unit]
Description=Socks Proxy ${AGENT_ID}
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
    echo "Agent installation failed: systemd service could not be started."
    echo "Service: ${SERVICE_NAME}"
    echo "Check status: systemctl status ${SERVICE_NAME}"
    echo "View logs: journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
    exit 1
  fi

  sleep 1
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Agent installation successful."
    echo "Service: ${SERVICE_NAME}"
    echo "Status: running"
    echo "Check status: systemctl status ${SERVICE_NAME}"
    echo "View logs (journal): journalctl -u ${SERVICE_NAME} -f"
    echo "File logs (if enabled): ${log_file}"
    echo "Config: ${CONFIG_PATH}"
    return 0
  fi

  echo "Agent installation failed: service is not running after startup."
  echo "Service: ${SERVICE_NAME}"
  echo "Check status: systemctl status ${SERVICE_NAME}"
  echo "View logs: journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
  echo "File logs (if enabled): ${log_file}"
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
    echo "检测到代理已在运行 (PID: ${found_pid})。"
    echo "为避免重复运行/覆盖，请先手动停止代理后再执行安装脚本。"
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

  local meta=""
  if command -v go >/dev/null 2>&1; then
    go_cmd="$(command -v go)"
  elif [[ -x "/usr/local/go/bin/go" ]]; then
    go_cmd="/usr/local/go/bin/go"
  fi

  if [[ -n "$go_cmd" ]]; then
    meta="$("$go_cmd" version -m "$bin" 2>/dev/null || true)"
    if [[ -n "$meta" ]]; then
      version="$(printf '%s\n' "$meta" | sed -n 's/.*main\.agentVersion=\([^ "]*\).*/\1/p' | head -n 1)"
      build_time="$(printf '%s\n' "$meta" | sed -n 's/.*main\.buildTimeUTC=\([^ "]*\).*/\1/p' | head -n 1)"
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
    version="$(grep -aEo 'main\.agentVersion=[^ "]*' "$bin" 2>/dev/null | sed 's/^main\.agentVersion=//' | head -n 1 || true)"
  fi
  if [[ -z "$build_time" ]]; then
    build_time="$(grep -aEo 'main\.buildTimeUTC=[^ "]*' "$bin" 2>/dev/null | sed 's/^main\.buildTimeUTC=//' | head -n 1 || true)"
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
    echo "Installed agent version: ${version}"
  else
    echo "Installed agent version: unknown"
  fi
  if [[ -n "$build_time" ]]; then
    echo "Installed agent build_time_utc: ${build_time}"
  fi
}

echo "Downloading agent from: $BIN_URL"
TMP_BIN="$(mktemp "${TMPDIR:-/tmp}/socks-proxy.XXXXXX")"
cleanup_tmp() {
  rm -f "$TMP_BIN"
}
trap cleanup_tmp EXIT

curl -fsSL "$BIN_URL" -o "$TMP_BIN"
chmod +x "$TMP_BIN"

if mv "$TMP_BIN" "$BIN_PATH" 2>/dev/null; then
  chmod +x "$BIN_PATH"
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "No permission to write ${BIN_PATH}, and sudo is not available."
    exit 1
  fi
  echo "No write permission for ${BIN_PATH}, retrying with sudo..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo mv "$TMP_BIN" "$BIN_PATH"
  sudo chmod +x "$BIN_PATH"
fi
extract_installed_version "$BIN_PATH"

# Remove stale local config so re-install always uses the latest args.
rm -f "$CONFIG_PATH"

# Persist runtime parameters for restarts and audits.
python3 - "$CONFIG_PATH" "$AGENT_ID" "$AGENT_SECRET" "$SERVER" <<'PY'
import json
import sys

config_path, agent_id, secret, server = sys.argv[1:]

cfg = {
    "agent_id": agent_id,
    "agent_secret": secret,
    "web_server_url": server,
}

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"Updated config: {config_path}")
PY

if [[ "$DAEMON_MODE" == "true" ]]; then
  echo "Starting agent in background..."
else
  echo "Starting agent in foreground..."
fi
RUN_ARGS=(run --agent-id "$AGENT_ID" --secret "$AGENT_SECRET" --web-server-url "$SERVER")
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  RUN_ARGS+=("${EXTRA_ARGS[@]}")
fi

if [[ "$DAEMON_MODE" == "true" ]]; then
  if systemd_available; then
    install_systemd_service
    exit 0
  fi

  if [[ -z "$PID_FILE" ]]; then
    PID_FILE="${INSTALL_DIR}/agent.pid"
  fi
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="${INSTALL_DIR}/agent.log"
  fi

  mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"

  echo "systemd not available; falling back to nohup background mode."
  if [[ "$OS" == "darwin" ]] && command -v caffeinate >/dev/null 2>&1; then
    # Keep system awake while the agent process is running.
    nohup caffeinate -dimsu "$BIN_PATH" "${RUN_ARGS[@]}" >>"$LOG_FILE" 2>&1 &
  else
    nohup "$BIN_PATH" "${RUN_ARGS[@]}" >>"$LOG_FILE" 2>&1 &
  fi
  NEW_PID=$!
  echo "$NEW_PID" >"$PID_FILE"
  echo "Agent installation successful."
  echo "Agent started in background."
  echo "PID: ${NEW_PID}"
  echo "PID file: ${PID_FILE}"
  echo "Log file: ${LOG_FILE}"
  echo "Config: ${CONFIG_PATH}"
  exit 0
fi

exec "$BIN_PATH" "${RUN_ARGS[@]}"
