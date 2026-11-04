#!/usr/bin/env bash
# Start Strata in Docker. First start downloads the model into ./data.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_env_file
refuse_deepseek_on_volta
refuse_coder_on_old_docker
mkdir -p "${DATA_DIR}"
warn_if_gpu_busy

if command -v strata >/dev/null 2>&1 || [[ -x "${HOME}/.local/bin/strata" ]]; then
  native_status="$("$(strata_bin)" launch --status 2>&1 || true)"
  if ! grep -q "Nothing from" <<<"${native_status}"; then
    echo "Native Strata appears to be serving. Stop it first: ./scripts/stop.sh" >&2
    echo "${native_status}" >&2
    exit 1
  fi
fi

if [[ -z "${API_KEY:-}" || "${API_KEY}" == change-me-please-use-a-long-random-key ]]; then
  echo "Set a real API_KEY in .env (openssl rand -hex 24)." >&2
  exit 1
fi

echo "Launching Docker Strata: ${STRATA_IMAGE}"
echo "Data dir: ${DATA_DIR}  API: $(base_url)"
echo "Watch download: docker compose logs -f"

docker compose up -d
docker compose ps
