#!/usr/bin/env bash
# Shared paths and .env loading for Strata helper scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.local/bin:${PATH}"

if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

DATA_DIR="${ROOT}/data"
FAMILY="${FAMILY:-qwen}"
MODEL="${MODEL:-IQ2_XS}"
CONTEXT="${CONTEXT:-32k}"
VISION="${VISION:-cpu}"
STRATA_BIND="${STRATA_BIND:-127.0.0.1}"
STRATA_PORT="${STRATA_PORT:-8080}"
STRATA_IMAGE="${STRATA_IMAGE:-ghcr.io/niko1221/strata:0.2.8-cuda12}"
GPU="${GPU:-0,1}"
GPU_ROLES="${GPU_ROLES:-}"
TUNE="${TUNE:-skip}"

# Extra native flags (set by fill_native_gpu_args).
NATIVE_GPU_ARGS=()

fill_native_gpu_args() {
  NATIVE_GPU_ARGS=()
  if [[ -n "${GPU}" ]]; then
    NATIVE_GPU_ARGS+=(--gpu "${GPU}")
  fi
}

strata_bin() {
  if command -v strata >/dev/null 2>&1; then
    command -v strata
    return
  fi
  if [[ -x "${HOME}/.local/bin/strata" ]]; then
    echo "${HOME}/.local/bin/strata"
    return
  fi
  echo "strata is not installed. Run ./scripts/install-native.sh" >&2
  return 1
}

require_env_file() {
  if [[ ! -f "${ROOT}/.env" ]]; then
    echo "Missing .env. Copy .env.v100.example (this 2x V100 host) or .env.example (Blackwell) to .env and set API_KEY." >&2
    exit 1
  fi
}

gpu_compute_users() {
  nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null || true
}

warn_if_gpu_busy() {
  local users
  users="$(gpu_compute_users | sed '/^\s*$/d' || true)"
  if [[ -n "${users}" ]]; then
    echo "Warning: the GPU already has compute processes:" >&2
    echo "${users}" >&2
    echo "Stop them (or the other Strata runner) before launch, or the model may OOM." >&2
  fi
}

base_url() {
  echo "http://${STRATA_BIND}:${STRATA_PORT}"
}
