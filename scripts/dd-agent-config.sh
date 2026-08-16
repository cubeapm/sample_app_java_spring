#!/usr/bin/env bash
# Switch Datadog agent export: dual-ship (Datadog + CubeAPM) or CubeAPM-only.
# Recreates datadog-agent so env vars reload (restart is not enough).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE="${COMPOSE_FILE:-$ROOT/docker-compose.yml}"
BEGIN="# BEGIN DD_AGENT_EXPORT"
END="# END DD_AGENT_EXPORT"
DEFAULT_SITE="us5.datadoghq.com"
DEFAULT_CUBE_HTTP="http://host.docker.internal:3130"
DUMMY_KEY="1234"

MODE=""
URL=""
API_KEY=""
SITE="$DEFAULT_SITE"
DO_RESTART=1

usage() {
  cat <<'EOF'
Usage:
  ./scripts/dd-agent-config.sh show
  ./scripts/dd-agent-config.sh dual --url URL --api-key KEY [--site us5.datadoghq.com] [--no-restart]
  ./scripts/dd-agent-config.sh cubeapm --url URL [--api-key KEY] [--no-restart]
  ./scripts/dd-agent-config.sh restart

  dual      Ship to Datadog and CubeAPM (DD_SITE + ADDITIONAL_ENDPOINTS)
  cubeapm   Ship only to CubeAPM (DD_DD_URL / DD_APM_DD_URL / logs)
  show      Print current export block (API key redacted)
  restart   Force-recreate datadog-agent

URL examples:
  https://clicker-scenic-gallon.ngrok-free.dev
  http://host.docker.internal:3130
EOF
}

redact() {
  sed -E 's/(DD_API_KEY=)[^[:space:]]+/\1***redacted***/'
}

normalize_url() {
  local u="$1"
  u="${u%/}"
  case "$u" in
    http://*|https://*) echo "$u" ;;
    localhost*|127.*|host.docker.internal*) echo "http://$u" ;;
    *) echo "https://$u" ;;
  esac
}

current_block() {
  awk -v b="$BEGIN" -v e="$END" '
    $0 ~ b {p=1; print; next}
    $0 ~ e {print; p=0; next}
    p {print}
  ' "$COMPOSE"
}

detect_mode() {
  local block
  block=$(current_block)
  if echo "$block" | grep -q '^[[:space:]]*- DD_ADDITIONAL_ENDPOINTS='; then
    echo dual
  elif echo "$block" | grep -q '^[[:space:]]*- DD_DD_URL='; then
    echo cubeapm
  else
    echo unknown
  fi
}

write_block() {
  local tmp
  tmp=$(mktemp)
  printf '%s\n' "$1" >"$tmp"
  python3 - "$COMPOSE" "$BEGIN" "$END" "$tmp" <<'PY'
import pathlib, sys
path, begin, end, tmp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
new = pathlib.Path(tmp).read_text().rstrip() + "\n"
text = pathlib.Path(path).read_text()
s = text.find(begin)
e = text.find(end)
if s < 0 or e < 0 or e < s:
    sys.exit(f"markers not found in {path}")
line_start = text.rfind("\n", 0, s) + 1
end_line_end = text.find("\n", e)
if end_line_end < 0:
    end_line_end = len(text)
else:
    end_line_end += 1
out = text[:line_start] + new + text[end_line_end:]
pathlib.Path(path).write_text(out)
PY
  rm -f "$tmp"
}

block_dual() {
  local url key site
  url=$(normalize_url "$URL")
  key="$API_KEY"
  site="$SITE"
  cat <<EOF
      $BEGIN
      # Required
      - DD_API_KEY=${key}
      - DD_SITE=${site}
      - DD_ADDITIONAL_ENDPOINTS={"${url}":["${DUMMY_KEY}"]}
      - DD_APM_ADDITIONAL_ENDPOINTS={"${url}":["${DUMMY_KEY}"]}

      # send metrics to CubeAPM
      # - DD_DD_URL=${DEFAULT_CUBE_HTTP}
      # send traces to CubeAPM
      # - DD_APM_DD_URL=${DEFAULT_CUBE_HTTP}
      # send logs to CubeAPM
      # - DD_LOGS_CONFIG_LOGS_DD_URL=${DEFAULT_CUBE_HTTP}
      # - DD_LOGS_ENABLED=true
      # - DD_LOGS_INJECTION=true
      # - DD_LOGS_CONFIG_USE_HTTP=true
      # - DD_LOGS_CONFIG_LOGS_NO_SSL=true
      # - DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true
      $END
EOF
}

block_cubeapm() {
  local url key ssl_line
  url=$(normalize_url "$URL")
  key="${API_KEY:-$DUMMY_KEY}"
  ssl_line="# - DD_LOGS_CONFIG_LOGS_NO_SSL=true"
  case "$url" in
    http://*) ssl_line="- DD_LOGS_CONFIG_LOGS_NO_SSL=true" ;;
  esac
  cat <<EOF
      $BEGIN
      # Required (dummy ok when not dual-shipping to Datadog)
      - DD_API_KEY=${key}

      # Dual-ship to Datadog (disabled)
      # - DD_SITE=${DEFAULT_SITE}
      # - DD_ADDITIONAL_ENDPOINTS={"https://YOUR-NGROK":["${DUMMY_KEY}"]}
      # - DD_APM_ADDITIONAL_ENDPOINTS={"https://YOUR-NGROK":["${DUMMY_KEY}"]}

      # send metrics to CubeAPM
      - DD_DD_URL=${url}
      # send traces to CubeAPM
      - DD_APM_DD_URL=${url}
      # send logs to CubeAPM
      - DD_LOGS_CONFIG_LOGS_DD_URL=${url}
      - DD_LOGS_ENABLED=true
      - DD_LOGS_INJECTION=true
      - DD_LOGS_CONFIG_USE_HTTP=true
      ${ssl_line}
      - DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL=true
      $END
EOF
}

cmd_show() {
  if [ ! -f "$COMPOSE" ]; then
    echo "ERROR: missing $COMPOSE"
    return 1
  fi
  echo "mode: $(detect_mode)"
  echo "file: $COMPOSE"
  echo "-----"
  current_block | redact
}

cmd_restart() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH"
    return 1
  fi
  echo "recreating datadog-agent (env reload)"
  docker compose -f "$COMPOSE" up -d --force-recreate datadog-agent
  echo "datadog-agent recreated"
}

apply_and_maybe_restart() {
  local label="$1"
  echo "wrote $label export to $COMPOSE"
  echo "mode: $(detect_mode)"
  current_block | redact
  if [ "$DO_RESTART" -eq 1 ]; then
    cmd_restart
  else
    echo "skipped recreate (--no-restart); run: ./scripts/dd-agent-config.sh restart"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    show|dual|cubeapm|restart) MODE="$1"; shift ;;
    --url) URL="${2:-}"; shift 2 ;;
    --api-key) API_KEY="${2:-}"; shift 2 ;;
    --site) SITE="${2:-}"; shift 2 ;;
    --no-restart) DO_RESTART=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

case "$MODE" in
  show) cmd_show ;;
  restart) cmd_restart ;;
  dual)
    [ -n "$URL" ] || { echo "ERROR: dual requires --url (CubeAPM ngrok/base URL)"; exit 1; }
    [ -n "$API_KEY" ] || { echo "ERROR: dual requires --api-key (Datadog API key)"; exit 1; }
    write_block "$(block_dual)"
    apply_and_maybe_restart dual
    ;;
  cubeapm)
    [ -n "$URL" ] || { echo "ERROR: cubeapm requires --url (CubeAPM base URL)"; exit 1; }
    write_block "$(block_cubeapm)"
    apply_and_maybe_restart cubeapm
    ;;
  *) usage; exit 1 ;;
esac
