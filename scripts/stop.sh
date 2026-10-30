#!/usr/bin/env bash
# Stop whichever Strata runner is up (native and/or Docker).
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

stopped=0

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx strata; then
  echo "Stopping Docker Strata (up to 2 minutes to unload the model)..."
  docker compose stop
  stopped=1
fi

if command -v strata >/dev/null 2>&1 || [[ -x "${HOME}/.local/bin/strata" ]]; then
  bin="$(strata_bin)"
  native_status="$("${bin}" launch --status 2>&1 || true)"
  if ! grep -q "Nothing from" <<<"${native_status}"; then
    echo "Stopping native Strata..."
    "${bin}" launch --stop || true
    stopped=1
  fi
fi

if [[ "${stopped}" -eq 0 ]]; then
  echo "No Strata runner was active."
else
  echo "Stopped."
fi
