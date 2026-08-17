#!/usr/bin/env bash
# Send N HTTP requests against the Datadog sample mesh.
# Compatible with macOS Bash 3.2.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

JAVA_BASE="${JAVA_BASE:-http://localhost:8000}"
NODE_BASE="${NODE_BASE:-http://localhost:8001}"
PYTHON_BASE="${PYTHON_BASE:-http://localhost:8002}"
PHP_BASE="${PHP_BASE:-http://localhost:8003}"
DOTNET_BASE="${DOTNET_BASE:-http://localhost:8004}"
ENDPOINTS_FILE="${ENDPOINTS_FILE:-$ROOT/scripts/endpoints.txt}"
PID_FILE="${TRAFFIC_PID_FILE:-$ROOT/tmp/traffic.pid}"
LOG_FILE="${TRAFFIC_LOG_FILE:-$ROOT/tmp/traffic.log}"
CONCURRENCY="${TRAFFIC_CONCURRENCY:-8}"

N=""
ROUNDS=""
SERVICES="java,nodejs,python,php,dotnet"
PATH_FILTER=""
MESH=0
BG=0
MODE="run" # run | status | stop

usage() {
  cat <<'EOF'
Usage: ./scripts/traffic.sh [N] [options]
       ./scripts/traffic.sh --rounds N [options]
       ./scripts/traffic.sh status|stop

  N              Number of HTTP requests (default 20)
  --rounds N     N full sweeps of the (filtered) catalog
  -s LIST        Services (default: java,nodejs,python,php,dotnet)
  -p PATH        Only hit endpoints whose path contains PATH
  --mesh         Also hit /{peer}/... proxies (error/mysql/redis/postgres/publish/external)
  --bg           Run in background (tmp/traffic.pid + tmp/traffic.log)
  -c N           Concurrency (default 8)
  status|stop    Background job control

Examples:
  ./scripts/traffic.sh 20
  ./scripts/traffic.sh 50 -s java,nodejs -p /redis
  ./scripts/traffic.sh --rounds 5 --mesh
  ./scripts/traffic.sh 200 --bg
EOF
}

normalize_svc() {
  case "$1" in
    node) echo nodejs ;;
    *) echo "$1" ;;
  esac
}

base_for() {
  case "$1" in
    java) echo "$JAVA_BASE" ;;
    nodejs) echo "$NODE_BASE" ;;
    python) echo "$PYTHON_BASE" ;;
    php) echo "$PHP_BASE" ;;
    dotnet) echo "$DOTNET_BASE" ;;
    *) echo "" ;;
  esac
}

peers_for() {
  case "$1" in
    java) echo "nodejs python php dotnet" ;;
    nodejs) echo "java python php dotnet" ;;
    python) echo "java nodejs php dotnet" ;;
    php) echo "java nodejs python dotnet" ;;
    dotnet) echo "java nodejs python php" ;;
  esac
}

# Write matched method|url|expect lines to $1
build_endpoint_list() {
  local out="$1"
  local method path expect note svc base url peer
  : > "$out"
  [ -f "$ENDPOINTS_FILE" ] || { echo "missing $ENDPOINTS_FILE" >&2; return 1; }

  OLDIFS="$IFS"
  IFS=','
  # shellcheck disable=SC2086
  set -- $SERVICES
  IFS="$OLDIFS"
  for raw in "$@"; do
    svc=$(normalize_svc "$raw")
    base=$(base_for "$svc")
    if [ -z "$base" ]; then
      echo "unknown service: $raw (known: java,nodejs,python,php,dotnet)" >&2
      continue
    fi
    while IFS='|' read -r method path expect note; do
      [ -z "${method:-}" ] && continue
      case "$method" in \#*) continue ;; esac
      if [ -n "$PATH_FILTER" ]; then
        case "$path" in
          *"$PATH_FILTER"*) ;;
          *) continue ;;
        esac
      fi
      echo "${method}|${base}${path}|${expect}" >> "$out"
    done < "$ENDPOINTS_FILE"

    if [ "$MESH" -eq 1 ]; then
      for peer in $(peers_for "$svc"); do
        for path_expect in \
          "/${peer}/external/123|200" \
          "/${peer}/error|200" \
          "/${peer}/mysql|200" \
          "/${peer}/redis|200" \
          "/${peer}/postgres|200" \
          "/${peer}/publish/kafka/topic-1/hello|200" \
          "/${peer}/publish/kafka/topic-2/hello|200" \
          "/${peer}/publish/rabbit/topic-1/hello|200" \
          "/${peer}/publish/rabbit/topic-2/hello|200"
        do
          path="${path_expect%%|*}"
          expect="${path_expect#*|}"
          if [ -n "$PATH_FILTER" ]; then
            case "$path" in
              *"$PATH_FILTER"*) ;;
              *) continue ;;
            esac
          fi
          echo "GET|${base}${path}|${expect}" >> "$out"
        done
      done
    fi
  done
}

run_traffic() {
  local ep_file work_file results_file ep_count i method url expect ok fail
  ep_file=$(mktemp)
  work_file=$(mktemp)
  results_file=$(mktemp)

  if ! build_endpoint_list "$ep_file"; then
    rm -f "$ep_file" "$work_file" "$results_file"
    return 1
  fi

  ep_count=$(grep -c '|' "$ep_file" || true)
  ep_count=${ep_count:-0}
  if [ "$ep_count" -eq 0 ]; then
    echo "no endpoints matched (services=$SERVICES path_filter=${PATH_FILTER:-none} mesh=$MESH)"
    rm -f "$ep_file" "$work_file" "$results_file"
    return 1
  fi

  if [ -n "$ROUNDS" ]; then
    N=$((ROUNDS * ep_count))
    echo "=== Traffic rounds=$ROUNDS endpoints=$ep_count requests=$N concurrency=$CONCURRENCY services=$SERVICES mesh=$MESH ==="
  else
    N="${N:-20}"
    echo "=== Traffic requests=$N endpoints=$ep_count concurrency=$CONCURRENCY services=$SERVICES mesh=$MESH ==="
  fi

  local probe
  probe=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "${JAVA_BASE}/external/1" 2>/dev/null) || true
  probe=${probe:-000}
  if [ "$probe" != "200" ] && [ "$probe" != "500" ]; then
    echo "stack not ready (GET ${JAVA_BASE}/external/1 -> $probe). Run: ./scripts/stack.sh start"
    rm -f "$ep_file" "$work_file" "$results_file"
    return 1
  fi

  i=0
  while [ "$i" -lt "$N" ]; do
    line_no=$(( (i % ep_count) + 1 ))
    sed -n "${line_no}p" "$ep_file" >> "$work_file"
    i=$((i + 1))
  done

  if command -v xargs >/dev/null 2>&1; then
    cat "$work_file" | xargs -P "$CONCURRENCY" -I '{}' bash -c '
      method=$(echo "$1" | cut -d"|" -f1)
      url=$(echo "$1" | cut -d"|" -f2)
      expect=$(echo "$1" | cut -d"|" -f3)
      if [ "$method" = "POST" ]; then
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 -X POST "$url" || echo 000)
      else
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$url" || echo 000)
      fi
      first=$(printf "%s" "$code" | cut -c1)
      if [ "$code" = "$expect" ] || [ "$first" = "2" ]; then
        echo "OK|$code|$expect|$method|$url"
      else
        echo "FAIL|$code|$expect|$method|$url"
      fi
    ' _ '{}' > "$results_file"
  else
    while IFS='|' read -r method url expect; do
      [ -z "${method:-}" ] && continue
      if [ "$method" = "POST" ]; then
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST "$url" || echo 000)
      else
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" || echo 000)
      fi
      first=$(printf '%s' "$code" | cut -c1)
      if [ "$code" = "$expect" ] || [ "$first" = "2" ]; then
        echo "OK|$code|$expect|$method|$url"
      else
        echo "FAIL|$code|$expect|$method|$url"
      fi
    done < "$work_file" > "$results_file"
  fi

  ok=$(grep -c '^OK|' "$results_file" || true)
  fail=$(grep -c '^FAIL|' "$results_file" || true)
  ok=${ok:-0}
  fail=${fail:-0}

  echo "=== DONE ok=$ok fail=$fail ==="
  if [ "$fail" -gt 0 ]; then
    echo "failures (up to 10):"
    grep '^FAIL|' "$results_file" | head -10 | while IFS='|' read -r _status code expect method url; do
      echo "  FAIL $method $url -> $code (expect $expect)"
    done
  fi
  rm -f "$ep_file" "$work_file" "$results_file"
  [ "$fail" -eq 0 ]
}

cmd_status() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "traffic running pid=$pid log=$LOG_FILE"
      tail -n 5 "$LOG_FILE" 2>/dev/null || true
      return 0
    fi
  fi
  echo "traffic not running"
  return 1
}

cmd_stop() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      pkill -P "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
      echo "stopped pid=$pid"
      return 0
    fi
    rm -f "$PID_FILE"
  fi
  echo "traffic not running"
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    status) MODE=status; shift ;;
    stop) MODE=stop; shift ;;
    --rounds)
      ROUNDS="${2:-}"
      [ -n "$ROUNDS" ] || { echo "--rounds needs a value"; exit 1; }
      shift 2
      ;;
    -s)
      SERVICES="${2:-}"
      [ -n "$SERVICES" ] || { echo "-s needs a value"; exit 1; }
      shift 2
      ;;
    -p)
      PATH_FILTER="${2:-}"
      [ -n "$PATH_FILTER" ] || { echo "-p needs a value"; exit 1; }
      shift 2
      ;;
    -c)
      CONCURRENCY="${2:-}"
      shift 2
      ;;
    --mesh) MESH=1; shift ;;
    --bg) BG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [ -z "$N" ]; then
        case "$1" in
          *[!0-9]*) echo "Unexpected arg: $1"; usage; exit 1 ;;
          *) N="$1"; shift ;;
        esac
      else
        echo "Unexpected arg: $1"
        usage
        exit 1
      fi
      ;;
  esac
done

case "$MODE" in
  status) cmd_status; exit $? ;;
  stop) cmd_stop; exit $? ;;
esac

mkdir -p "$ROOT/tmp"

if [ "$BG" -eq 1 ]; then
  if [ -f "$PID_FILE" ]; then
    old=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      echo "traffic already running pid=$old"
      exit 1
    fi
  fi
  reargs=()
  [ -n "$N" ] && reargs+=("$N")
  [ -n "$ROUNDS" ] && reargs+=(--rounds "$ROUNDS")
  reargs+=(-s "$SERVICES")
  [ -n "$PATH_FILTER" ] && reargs+=(-p "$PATH_FILTER")
  reargs+=(-c "$CONCURRENCY")
  [ "$MESH" -eq 1 ] && reargs+=(--mesh)
  nohup "$ROOT/scripts/traffic.sh" "${reargs[@]}" >"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  echo "started background traffic pid=$(cat "$PID_FILE") log=$LOG_FILE"
  exit 0
fi

run_traffic
