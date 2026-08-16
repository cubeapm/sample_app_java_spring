#!/usr/bin/env bash
# Legacy wrapper: N hits of /call/all across all apps (default 50).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
N="${1:-50}"
exec "$ROOT/scripts/traffic.sh" "$N" -p /call/all
