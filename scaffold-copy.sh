#!/usr/bin/env bash
set -euo pipefail

# Stage 10 cross-platform launcher. Tenant/repository values come from
# lz-config.json or environment variables; this script never prompts.

scaffold_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_path="${LZ_CONFIG_PATH:-./lz-config.json}"
rendered_path="${LZ_RENDERED_PATH:-./rendered-output}"
target_path="${LZ_SCAFFOLD_TARGET:-./scaffold-output}"
evidence_path="${LZ_SCAFFOLD_EVIDENCE:-./scaffold-evidence}"

args=(
  -NoLogo
  -NoProfile
  -File "$scaffold_root/scaffold-copy.ps1"
  -ConfigPath "$config_path"
  -RenderedDirectory "$rendered_path"
  -TargetDirectory "$target_path"
  -EvidenceDirectory "$evidence_path"
)

[[ "${LZ_SCAFFOLD_APPLY:-false}" == "true" ]] && args+=(-Apply)
[[ "${LZ_SCAFFOLD_FORCE:-false}" == "true" ]] && args+=(-Force)
[[ "${LZ_SCAFFOLD_CREATE_REPOSITORY:-true}" == "false" ]] && args+=(-SkipRepositoryCreate)
[[ "${LZ_SCAFFOLD_PUSH:-true}" == "false" ]] && args+=(-SkipPush)

exec pwsh "${args[@]}"
