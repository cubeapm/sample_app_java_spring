#!/usr/bin/env bash
# Legacy wrapper: N full local+peer catalog sweeps (default 5).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
N="${1:-5}"
exec "$ROOT/scripts/traffic.sh" --rounds "$N" --mesh
