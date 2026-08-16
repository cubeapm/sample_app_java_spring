#!/usr/bin/env bash
# Thin wrapper for legacy callers. Prefer: ./scripts/traffic.sh [N]
# Arg1 = request count (default 20). Arg2 = agent label (ignored; for log compat).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
N="${1:-20}"
exec "$ROOT/scripts/traffic.sh" "$N"
