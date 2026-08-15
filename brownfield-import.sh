#!/usr/bin/env bash
set -euo pipefail

# Stage 11 launcher. It generates reviewable artifacts only and never runs
# terraform import. All customer-specific values come from files or variables.

echo "brownfield-import is quarantined (docs/refactor/CLASSIFICATION.md, UNRESOLVED-2):" >&2
echo "its import targets reference the retired bespoke modules, not the AVM corpus." >&2
exit 1

import_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_path="${LZ_CONFIG_PATH:-./lz-config.json}"
discovery_path="${LZ_DISCOVERY_PATH:-./discovery-inventory.json}"
classification_path="${LZ_BROWNFIELD_CLASSIFICATIONS:-./brownfield-classifications.json}"
rendered_path="${LZ_RENDERED_PATH:-./rendered-output}"
evidence_path="${LZ_IMPORT_EVIDENCE:-./brownfield-evidence}"

args=(
  -NoLogo
  -NoProfile
  -File "$import_root/brownfield-import.ps1"
  -ConfigPath "$config_path"
  -DiscoveryPath "$discovery_path"
  -ClassificationPath "$classification_path"
  -RenderedDirectory "$rendered_path"
  -EvidenceDirectory "$evidence_path"
)

[[ "${LZ_IMPORT_APPLY:-false}" == "true" ]] && args+=(-Apply)
[[ "${LZ_IMPORT_ALLOW_STALE:-false}" == "true" ]] && args+=(-AllowStaleInventory)

exec pwsh "${args[@]}"
