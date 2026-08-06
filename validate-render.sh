#!/usr/bin/env bash
set -euo pipefail

# Post-render validation gate launcher. Verifies the rendered tree is
# deployable before the scaffold publishes it. Read-only against the rendered
# tree: terraform init runs in an isolated scratch copy that is deleted
# afterwards. Values come from environment variables; this script never
# prompts.

validate_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rendered_path="${LZ_RENDERED_PATH:-./rendered-output}"
evidence_path="${LZ_VALIDATE_EVIDENCE:-./validate-evidence}"

args=(
  -NoLogo
  -NoProfile
  -File "$validate_root/validate-render.ps1"
  -RenderedDirectory "$rendered_path"
  -EvidenceDirectory "$evidence_path"
)

[[ "${LZ_VALIDATE_STRICT:-false}" == "true" ]] && args+=(-Strict)
[[ "${LZ_VALIDATE_SKIP_SECURITY_SCAN:-false}" == "true" ]] && args+=(-SkipSecurityScan)
[[ "${LZ_VALIDATE_SKIP_LINT:-false}" == "true" ]] && args+=(-SkipLint)

exec pwsh "${args[@]}"
