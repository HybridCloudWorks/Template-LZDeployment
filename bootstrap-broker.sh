#!/usr/bin/env bash
set -euo pipefail

# Stage 9 cross-platform launcher. All tenant/repository-specific values come
# from lz-config.json or environment variables; this script never prompts.

broker_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_path="${LZ_CONFIG_PATH:-./lz-config.json}"
discovery_path="${LZ_DISCOVERY_PATH:-./discovery-inventory.json}"
output_path="${LZ_BOOTSTRAP_OUTPUT:-./bootstrap-output}"

args=(
  -NoLogo
  -NoProfile
  -File "$broker_root/bootstrap-broker.ps1"
  -ConfigPath "$config_path"
  -DiscoveryPath "$discovery_path"
  -OutputDirectory "$output_path"
)

if [[ "${LZ_BOOTSTRAP_APPLY:-false}" == "true" ]]; then
  args+=(-Apply)
fi

if [[ "${LZ_BOOTSTRAP_ALLOW_NOT_READY:-false}" == "true" ]]; then
  args+=(-AllowNotReady)
fi

exec pwsh "${args[@]}"

