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
STRATA_IMAGE="${STRATA_IMAGE:-ghcr.io/niko1221/strata:0.2.9-cuda12}"
GPU="${GPU:-0,1}"
GPU_ROLES="${GPU_ROLES:-}"
TUNE="${TUNE:-skip}"
SPEED="${SPEED:-}"
DRAFTING="${DRAFTING:-}"

# Extra native flags (set by fill_native_launch_args).
NATIVE_GPU_ARGS=()
NATIVE_LAUNCH_ARGS=()

fill_native_gpu_args() {
  NATIVE_GPU_ARGS=()
  if [[ -n "${GPU}" ]]; then
    NATIVE_GPU_ARGS+=(--gpu "${GPU}")
  fi
}

fill_native_launch_args() {
  fill_native_gpu_args
  NATIVE_LAUNCH_ARGS=("${NATIVE_GPU_ARGS[@]}")
  if [[ -n "${SPEED}" ]]; then
    NATIVE_LAUNCH_ARGS+=(--speed "${SPEED}")
  fi
  if [[ -n "${DRAFTING}" ]]; then
    NATIVE_LAUNCH_ARGS+=(--drafting "${DRAFTING}")
  fi
}

family_is_deepseek() {
  local f
  f="$(printf '%s' "${FAMILY}" | tr '[:upper:]' '[:lower:]')"
  [[ "${f}" == deepseek41 || "${f}" == deepseek || "${f}" == deepseek-v4.1-flash ]]
}

model_is_ista_das_coder() {
  local m
  m="$(printf '%s' "${MODEL}" | tr '[:upper:]' '[:lower:]')"
  [[ "${m}" == ista-das-coder ]]
}

is_volta_or_cuda12() {
  if [[ "${STRATA_IMAGE}" == *cuda12* ]]; then
    return 0
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | grep -qE '^7\.0'; then
      return 0
    fi
  fi
  return 1
}

warn_deepseek_on_volta() {
  if family_is_deepseek && is_volta_or_cuda12; then
    echo "Warning: DeepSeek is not supported on CUDA 12 / Volta (no official strata-dsv41 package)." >&2
    echo "Official engines are CUDA 13 for RTX 30/40/50 (sm_86/89/120). Plan is allowed." >&2
    echo "Launch scripts refuse unless STRATA_FORCE_UNSUPPORTED=1 — that can still download ~191 GB and then fail to serve." >&2
    echo "Supported path: native 0.2.10 on the Blackwell box (cp .env.blackwell.deepseek.example .env)." >&2
    echo
  fi
}

refuse_deepseek_on_volta() {
  if family_is_deepseek && is_volta_or_cuda12; then
    if [[ "${STRATA_FORCE_UNSUPPORTED:-}" == "1" ]]; then
      echo "Warning: STRATA_FORCE_UNSUPPORTED=1 — launching DeepSeek on CUDA 12 / Volta anyway." >&2
      echo "Expect no engine, then a ~191 GB download that cannot serve." >&2
      return 0
    fi
    echo "Refusing DeepSeek on this CUDA 12 / Volta host." >&2
    echo "Official strata-dsv41 packages are CUDA 13 for RTX 30/40/50 (sm_86/89/120)." >&2
    echo "Run ./scripts/plan.sh to see Strata's own message." >&2
    echo "To override (will likely download ~191 GB and still not serve): STRATA_FORCE_UNSUPPORTED=1 $0" >&2
    echo "Supported path: native 0.2.10 on the Blackwell box — cp .env.blackwell.deepseek.example .env" >&2
    exit 1
  fi
}

refuse_coder_on_old_docker() {
  if model_is_ista_das_coder && [[ "${STRATA_IMAGE}" != *0.2.10* ]]; then
    echo "ISTA-DAS-Coder needs Strata 0.2.10. Docker images in this wrapper are still 0.2.9 (GHCR has no 0.2.10 tag yet)." >&2
    echo "Use ./scripts/launch-native.sh on the Blackwell box after native 0.2.10." >&2
    exit 1
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
    echo "Missing .env. Copy .env.v100.example (this 2x V100 host, Qwen) or .env.example (Blackwell, Qwen) to .env and set API_KEY." >&2
    echo "DeepSeek Coder: .env.blackwell.deepseek.example on the RTX host (native 0.2.10). V100 profile is plan-only." >&2
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
