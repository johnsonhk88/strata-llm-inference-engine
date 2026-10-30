#!/usr/bin/env bash
# Show native, Docker, GPU, and API health.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "== GPU =="
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv
echo
echo "== GPU compute processes =="
gpu_compute_users || echo "(none)"
echo
echo "== Native =="
if command -v strata >/dev/null 2>&1 || [[ -x "${HOME}/.local/bin/strata" ]]; then
  bin="$(strata_bin)"
  "${bin}" --version || true
  "${bin}" launch --status || true
else
  echo "strata CLI not installed (./scripts/install-native.sh)"
fi
echo
echo "== Docker =="
if docker compose ps 2>/dev/null | grep -q strata; then
  docker compose ps
else
  echo "compose service not running"
fi
echo
echo "== API $(base_url) =="
if curl -fsS --max-time 3 "$(base_url)/health" >/dev/null 2>&1; then
  curl -fsS "$(base_url)/health"
  echo
  if [[ -n "${API_KEY:-}" && "${API_KEY}" != change-me-please-use-a-long-random-key ]]; then
    curl -fsS -H "Authorization: Bearer ${API_KEY}" "$(base_url)/v1/models" || true
    echo
  fi
else
  echo "not reachable"
fi
