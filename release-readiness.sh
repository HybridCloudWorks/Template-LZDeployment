#!/usr/bin/env bash
set -euo pipefail

args=(-NoProfile -File "$(dirname "$0")/release-readiness.ps1")
if [[ "${LZ_RELEASE_ALLOW_INCOMPLETE:-false}" == "true" ]]; then
  args+=(-AllowIncomplete)
fi

exec pwsh "${args[@]}"
