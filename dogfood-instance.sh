#!/usr/bin/env bash
set -euo pipefail

mode="${LZ_DOGFOOD_MODE:-Render}"
args=(-NoProfile -File "$(dirname "$0")/dogfood-instance.ps1" -Mode "$mode")

if [[ "${LZ_DOGFOOD_APPLY:-false}" == "true" ]]; then
  args+=(-AllowApply)
fi

exec pwsh "${args[@]}"
