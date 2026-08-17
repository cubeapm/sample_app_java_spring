#!/usr/bin/env bash
# Start/stop/status/catalog for the Datadog sample mesh.
# All waiting happens here — agents should run this once and not poll.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

JAVA_BASE="${JAVA_BASE:-http://localhost:8000}"
NODE_BASE="${NODE_BASE:-http://localhost:8001}"
PYTHON_BASE="${PYTHON_BASE:-http://localhost:8002}"
PHP_BASE="${PHP_BASE:-http://localhost:8003}"
DOTNET_BASE="${DOTNET_BASE:-http://localhost:8004}"
PROBE_PATH="${PROBE_PATH:-/external/1}"
ENDPOINTS_FILE="${ENDPOINTS_FILE:-$ROOT/scripts/endpoints.txt}"
CLOUD_NET_MODE_FILE="${CLOUD_NET_MODE_FILE:-$ROOT/tmp/cloud-net-mode}"

# name|port|base_url
APPS="java|8000|${JAVA_BASE}
nodejs|8001|${NODE_BASE}
python|8002|${PYTHON_BASE}
php|8003|${PHP_BASE}
dotnet|8004|${DOTNET_BASE}"

usage() {
  cat <<'EOF'
Usage: ./scripts/stack.sh <start|stop|down|status|catalog|restart-agent>

  start    Ensure Docker (cloud VMs), detached compose up, wait until apps ready
  stop     docker compose stop (keeps images/volumes; fast restart)
  down     docker compose down
  status   compose ps + HTTP probes
  catalog  languages, ports, endpoints, APM names
  restart-agent  force-recreate datadog-agent (reload env)

Cloud / CubeAPM:
  start calls ./scripts/cloud-docker.sh ensure (no-op on macOS).
  CUBEAPM_URL=https://<ngrok> ./scripts/stack.sh start
    writes CubeAPM-only export before up. On cloud VMs the URL must be public
    (ngrok); host.docker.internal is the VM, not your laptop.
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

all_apps_ready() {
  local name port base code
  while IFS='|' read -r name port base; do
    [ -z "${name:-}" ] && continue
    code=$(http_code "${base}${PROBE_PATH}" 1)
    if [ "$code" != "200" ] && [ "$code" != "500" ]; then
      return 1
    fi
  done <<EOF
$APPS
EOF
  return 0
}

print_status_table() {
  echo "SERVICE  PORT   HTTP  URL"
  echo "$APPS" | while IFS='|' read -r name port base; do
    [ -z "${name:-}" ] && continue
    code=$(http_code "${base}${PROBE_PATH}" 2)
    printf "%-8s %-6s %-4s  %s%s\n" "$name" "$port" "$code" "$base" "$PROBE_PATH"
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
  docker compose images -q java 2>/dev/null | grep -q .
}

containers_exist() {
  docker compose ps -a --format '{{.Name}}' 2>/dev/null | grep -q .
}

wait_apps() {
  local timeout_s="$1"
  local deadline start_ts now code name port base not_ready
  start_ts=$(date +%s)
  deadline=$((start_ts + timeout_s))

  echo "waiting for apps (timeout=${timeout_s}s, probe=${PROBE_PATH})..."
  while true; do
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      break
    fi
    if all_apps_ready; then
      echo "$APPS" | while IFS='|' read -r name port base; do
        [ -z "${name:-}" ] && continue
        code=$(http_code "${base}${PROBE_PATH}" 1)
        echo "ready: $name ($code)"
      done
      return 0
    fi
    sleep 2
  done

  not_ready=0
  echo "$APPS" | while IFS='|' read -r name port base; do
    [ -z "${name:-}" ] && continue
    code=$(http_code "${base}${PROBE_PATH}" 2)
    if [ "$code" = "200" ] || [ "$code" = "500" ]; then
      echo "ready: $name ($code)"
    else
      echo "NOT READY: $name (last=$code)"
    fi
  done
  if all_apps_ready; then
    return 0
  fi
  return 1
}

apply_cubeapm_url() {
  [ -n "${CUBEAPM_URL:-}" ] || return 0
  local extra=()
  if "$ROOT/scripts/cloud-docker.sh" is-cloud >/dev/null; then
    extra+=(--require-public)
  fi
  echo "CUBEAPM_URL set; writing cubeapm export (no recreate yet)"
  "$ROOT/scripts/dd-agent-config.sh" cubeapm --url "$CUBEAPM_URL" --no-restart "${extra[@]}"
}

ensure_runtime() {
  "$ROOT/scripts/cloud-docker.sh" ensure
}

apply_compose_file() {
  local mode
  mode=$(cat "$CLOUD_NET_MODE_FILE" 2>/dev/null || echo bridge)
  if [ "$mode" = host ]; then
    export COMPOSE_FILE="$ROOT/docker-compose.yml:$ROOT/docker-compose.cloud.yml"
    echo "compose overlay: host network"
  else
    export COMPOSE_FILE="$ROOT/docker-compose.yml"
  fi
}

cmd_start() {
  ensure_runtime || return 1
  apply_compose_file
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH"
    return 1
  fi
  local agent_existed=0
  if docker compose ps -a --format '{{.Name}}' 2>/dev/null | grep -qx datadog-agent; then
    agent_existed=1
  fi
  apply_cubeapm_url || return 1
  if all_apps_ready; then
    echo "fast-path: stack already ready"
    if [ -n "${CUBEAPM_URL:-}" ] && [ "$agent_existed" -eq 1 ]; then
      "$ROOT/scripts/dd-agent-config.sh" restart || return 1
    fi
    print_status_table
    return 0
  fi

  local timeout_s=120

  if images_exist || containers_exist; then
    echo "warm start: docker compose up -d"
    docker compose up -d
  else
    echo "cold start: docker compose up -d --build"
    timeout_s=240
    docker compose up -d --build
  fi
  if [ -n "${CUBEAPM_URL:-}" ] && [ "$agent_existed" -eq 1 ]; then
    "$ROOT/scripts/dd-agent-config.sh" restart || return 1
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
  apply_compose_file
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH"
    return 1
  fi
  docker compose stop
  echo "stopped (use start for warm restart; down to remove containers)"
}

cmd_down() {
  apply_compose_file
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH"
    return 1
  fi
  docker compose down
  echo "down"
}

cmd_status() {
  apply_compose_file
  print_status_table
  if all_apps_ready; then
    echo "overall: ready"
    return 0
  fi
  echo "overall: not ready"
  return 1
}

cmd_restart_agent() {
  apply_compose_file
  "$ROOT/scripts/dd-agent-config.sh" restart
}

cmd_catalog() {
  cat <<EOF
Languages / apps (DD_ENV=dd-ext2):
  java     port 8000  ${JAVA_BASE}     cube_sample_java_spring_boot_datadog
  nodejs   port 8001  ${NODE_BASE}     cube_sample_node_express_datadog
  python   port 8002  ${PYTHON_BASE}   cube_sample_python_flask_datadog
  php      port 8003  ${PHP_BASE}      cube_sample_php_datadog
  dotnet   port 8004  ${DOTNET_BASE}   cube_sample_dotnet_aspnet_datadog

Peer path token: nodejs (not node). Kafka/Rabbit: topic-1, topic-2.

Infra:
  mysql      port 3306
  postgres   port 5432
  redis      internal (redis-host)
  kafka      port 9092
  rabbitmq   port 5672 (UI 15672)
  datadog-agent  traces :8126 (internal)

Local endpoints (from scripts/endpoints.txt; same on every app):
EOF
  if [ -f "$ENDPOINTS_FILE" ]; then
    grep -v '^#' "$ENDPOINTS_FILE" | grep -v '^$' | while IFS='|' read -r method path expect note; do
      printf "  %-6s %-50s expect=%s  # %s\n" "$method" "$path" "$expect" "$note"
    done
  else
    echo "  (missing $ENDPOINTS_FILE)"
  fi
  cat <<'EOF'

Peer proxies (not in endpoints.txt; use traffic.sh --mesh):
  GET /{lang}/external/{id}  GET /{lang}/error  GET /{lang}/mysql
  GET /{lang}/redis  GET /{lang}/postgres
  GET /{lang}/publish/kafka/{topic}/{text}
  GET /{lang}/publish/rabbit/{topic}/{text}

Traffic: ./scripts/traffic.sh [N] [-s java,nodejs,python,php,dotnet] [-p /path] [--rounds N] [--mesh] [--bg]
Cloud:   ./scripts/cloud-docker.sh ensure   # install/start Docker + bridge NAT (no-op on macOS)
         CUBEAPM_URL=https://<ngrok> ./scripts/stack.sh start
EOF
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    start) cmd_start ;;
    stop) cmd_stop ;;
    down) cmd_down ;;
    status) cmd_status ;;
    catalog) cmd_catalog ;;
    restart-agent) cmd_restart_agent ;;
    -h|--help|help|"") usage; [ -n "$cmd" ];;
    *) echo "Unknown command: $cmd"; usage; return 1 ;;
  esac
}

main "$@"
