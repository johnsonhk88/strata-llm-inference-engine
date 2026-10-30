#!/usr/bin/env bash
# Install the official Strata Terminal into ~/.local (no source checkout).
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

echo "Downloading official install.sh from Niko1221/Strata latest release..."
curl -fsSL "https://github.com/Niko1221/Strata/releases/latest/download/install.sh" -o "${tmp}/install.sh"
sh "${tmp}/install.sh"

export PATH="${HOME}/.local/bin:${PATH}"
if ! command -v strata >/dev/null 2>&1; then
  echo "Installer finished but 'strata' is not on PATH."
  echo "Add this to your shell config: export PATH=\"\$HOME/.local/bin:\$PATH\""
  if [[ -x "${HOME}/.local/bin/strata" ]]; then
    "${HOME}/.local/bin/strata" --version
  fi
  exit 0
fi

strata --version
echo
echo "Next: ./scripts/plan.sh     (no download)"
echo "      ./scripts/launch-native.sh   (downloads the model on first run)"
