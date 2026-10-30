#!/usr/bin/env bash
# Start Strata with the native Terminal. First run downloads the model into ./data.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_env_file
bin="$(strata_bin)"
mkdir -p "${DATA_DIR}"
warn_if_gpu_busy

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx strata; then
  echo "Docker Strata is already running. Stop it first: ./scripts/stop.sh" >&2
  exit 1
fi

if [[ -z "${API_KEY:-}" || "${API_KEY}" == change-me-please-use-a-long-random-key ]]; then
  echo "Set a real API_KEY in .env (openssl rand -hex 24)." >&2
  exit 1
fi

echo "Launching native Strata: ${FAMILY}/${MODEL} on $(base_url)"
echo "Data dir: ${DATA_DIR}"
echo "First start can take a long time (model download + prepare)."

exec "${bin}" launch \
  --family "${FAMILY}" \
  --model "${MODEL}" \
  --context "${CONTEXT}" \
  --vision "${VISION}" \
  --data-dir "${DATA_DIR}" \
  --access local \
  --port "${STRATA_PORT}" \
  --api-key "${API_KEY}" \
  --save-preset local \
  --yes \
  --no-tui
