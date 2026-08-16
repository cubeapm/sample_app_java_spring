#!/usr/bin/env bash
# Thin wrapper: N hits of /api (closest fan-out analogue on this branch).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
N="${1:-50}"
exec "$ROOT/scripts/traffic.sh" "$N" -p /api
