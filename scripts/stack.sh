#!/usr/bin/env bash
# Start/stop/status/catalog for the sample Docker stack.
# All waiting happens here — agents should run this once and not poll.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

JAVA_BASE="${JAVA_BASE:-http://localhost:8000}"
PROBE_PATH="${PROBE_PATH:-/}"
ENDPOINTS_FILE="${ENDPOINTS_FILE:-$ROOT/scripts/endpoints.txt}"

# App services to wait on (name|base_url)
APPS="java|${JAVA_BASE}"

usage() {
  cat <<'EOF'
Usage: ./scripts/stack.sh <start|stop|down|status|catalog>

  start    Detached compose up, wait until apps are HTTP-ready, print status
  stop     docker compose stop (keeps images/volumes; fast restart)
  down     docker compose down
  status   compose ps + HTTP probes
  catalog  languages, ports, endpoints
EOF
}

http_code() {
  local url="$1" timeout="${2:-2}" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null) || true
  if [ -z "$code" ]; then
    code=000
  fi
  echo "$code"
}

probe_ok() {
  local code
  code=$(http_code "${JAVA_BASE}${PROBE_PATH}" 1)
  [ "$code" = "200" ] || [ "$code" = "500" ]
}

all_apps_ready() {
  local entry name base code
  for entry in $APPS; do
    name="${entry%%|*}"
    base="${entry#*|}"
    code=$(http_code "${base}${PROBE_PATH}" 1)
    if [ "$code" != "200" ] && [ "$code" != "500" ]; then
      return 1
    fi
  done
  return 0
}

print_status_table() {
  local entry name base code
  echo "SERVICE  PORT   HTTP  URL"
  for entry in $APPS; do
    name="${entry%%|*}"
    base="${entry#*|}"
    code=$(http_code "${base}${PROBE_PATH}" 2)
    printf "%-8s %-6s %-4s  %s%s\n" "$name" "8000" "$code" "$base" "$PROBE_PATH"
  done
  echo
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker: not installed"
    return 0
  fi
  docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null \
    || docker compose ps
}

images_exist() {
  # Warm if the java service image (or a previously built one) is present.
  docker compose images -q java 2>/dev/null | grep -q .
}

containers_exist() {
  docker compose ps -a --format '{{.Name}}' 2>/dev/null | grep -q .
}

wait_apps() {
  local timeout_s="$1"
  local deadline start_ts now code entry name base not_ready
  start_ts=$(date +%s)
  deadline=$((start_ts + timeout_s))

  echo "waiting for apps (timeout=${timeout_s}s, probe=${PROBE_PATH})..."
  while true; do
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      break
    fi
    if all_apps_ready; then
      for entry in $APPS; do
        name="${entry%%|*}"
        base="${entry#*|}"
        code=$(http_code "${base}${PROBE_PATH}" 1)
        echo "ready: $name ($code)"
      done
      return 0
    fi
    sleep 2
  done

  not_ready=0
  for entry in $APPS; do
    name="${entry%%|*}"
    base="${entry#*|}"
    code=$(http_code "${base}${PROBE_PATH}" 2)
    if [ "$code" = "200" ] || [ "$code" = "500" ]; then
      echo "ready: $name ($code)"
    else
      echo "NOT READY: $name (last=$code)"
      not_ready=1
    fi
  done
  return "$not_ready"
}

cmd_start() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH"
    return 1
  fi
  if all_apps_ready; then
    echo "fast-path: stack already ready"
    print_status_table
    return 0
  fi

  local timeout_s=90

  if images_exist || containers_exist; then
    echo "warm start: docker compose up -d"
    docker compose up -d
  else
    echo "cold start: docker compose up -d --build"
    timeout_s=180
    docker compose up -d --build
  fi

  if ! wait_apps "$timeout_s"; then
    echo "ERROR: apps not ready within ${timeout_s}s"
    print_status_table
    return 1
  fi
  print_status_table
  return 0
}

cmd_stop() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH"
    return 1
  fi
  docker compose stop
  echo "stopped (use start for warm restart; down to remove containers)"
}

cmd_down() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH"
    return 1
  fi
  docker compose down
  echo "down"
}

cmd_status() {
  print_status_table
  if all_apps_ready; then
    echo "overall: ready"
    return 0
  fi
  echo "overall: not ready"
  return 1
}

cmd_catalog() {
  cat <<EOF
Languages / services:
  java     port 8000  ${JAVA_BASE}
Infra:
  mysql    port 3306  (container cube_java_springboot_mysql)
  redis    port 6379  (container cube_java_springboot_redis, no host publish)

Endpoints (from scripts/endpoints.txt):
EOF
  if [ -f "$ENDPOINTS_FILE" ]; then
    grep -v '^#' "$ENDPOINTS_FILE" | grep -v '^$' | while IFS='|' read -r method path expect note; do
      printf "  %-6s %-50s expect=%s  # %s\n" "$method" "$path" "$expect" "$note"
    done
  else
    echo "  (missing $ENDPOINTS_FILE)"
  fi
  echo
  echo "Traffic: ./scripts/traffic.sh [N] [-s java] [-p /path] [--rounds N] [--bg]"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    start) cmd_start ;;
    stop) cmd_stop ;;
    down) cmd_down ;;
    status) cmd_status ;;
    catalog) cmd_catalog ;;
    -h|--help|help|"") usage; [ -n "$cmd" ];;
    *) echo "Unknown command: $cmd"; usage; return 1 ;;
  esac
}

main "$@"
