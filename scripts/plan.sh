#!/usr/bin/env bash
# Print what a launch would download/start. Nothing is changed.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

bin="$(strata_bin)"
mkdir -p "${DATA_DIR}"
fill_native_gpu_args

echo "Plan: family=${FAMILY} model=${MODEL} context=${CONTEXT} vision=${VISION} gpu=${GPU:-auto} data=${DATA_DIR}"
echo "Image (Docker): ${STRATA_IMAGE}"
echo
"${bin}" launch \
  --plan \
  --family "${FAMILY}" \
  --model "${MODEL}" \
  --context "${CONTEXT}" \
  --vision "${VISION}" \
  --data-dir "${DATA_DIR}" \
  --access local \
  --port "${STRATA_PORT}" \
  "${NATIVE_GPU_ARGS[@]}"
