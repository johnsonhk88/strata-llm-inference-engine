#!/usr/bin/env bash
# Print what a launch would download/start. Nothing is changed.
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

bin="$(strata_bin)"
mkdir -p "${DATA_DIR}"
fill_native_launch_args
warn_deepseek_on_volta

echo "Plan: family=${FAMILY} model=${MODEL} context=${CONTEXT} vision=${VISION} gpu=${GPU:-auto} data=${DATA_DIR}"
echo "Image (Docker): ${STRATA_IMAGE}"
if [[ -n "${SPEED}" ]]; then
  echo "Speed: ${SPEED}"
fi
if [[ -n "${DRAFTING}" ]]; then
  echo "Drafting: ${DRAFTING}"
fi
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
  "${NATIVE_LAUNCH_ARGS[@]}"
