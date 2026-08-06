# Decision 0005 — Scaffold apply refuses unvalidated or stale-validated renders

**Date**: 2026-08-06
**Status**: Accepted
**Context**: The customer motion requires that generated code is validated
through automated pre-deployment checks — terraform validate, formatting
verification, policy compliance evaluation, security scanning, and dependency
integrity — and that execution terminates with actionable remediation when any
check fails, so that no incomplete, non-compliant, or undeployable artifact is
ever committed to the customer's landing-zone repository. Before this decision,
nothing between the renderer (Stage 5) and the scaffold (Stage 10) ran
`terraform init`/`validate`, a blocking format check, lint, or a security scan
against the rendered tree: the renderer's `terraform fmt` pass only warns on
failure, and Factory CI (Stage 12) validates the *source* corpus, not the tree
a specific configuration actually produced.

## Decision

A **post-render validation gate** (`validate-render.ps1` / `.sh`, module
`factory/validate/LZFactory.Validate.psm1`) runs between render and scaffold,
and **scaffold apply refuses a render whose validation evidence is missing,
failed, or stale**. The gate:

1. Runs eight gates — V01 inventory-integrity, V02 format-verification,
   V03 dependency-integrity (`terraform init -backend=false` in every rendered
   `*.tf` directory), V04 terraform-validate, V05 workflow-pinning-policy,
   V06 provider-constraint-integrity, V07 lint (tflint), V08 security-scan
   (checkov/tfsec/trivy) — and runs **all** of them even after one fails, so
   `validate-report.json` shows the complete remediation surface.
2. Writes `validate-report.json` plus per-gate logs under
   `LZ_VALIDATE_EVIDENCE`, binds the evidence to the exact render via the
   SHA-256 of `render-manifest.json` (the same hash the scaffold inventory
   computes), and throws when any gate failed, naming the failing gate IDs.
3. Never modifies the rendered tree: the tool-driven gates run against a
   scratch copy under the system temp directory, so `terraform init`'s
   `.terraform/` directories cannot poison the scaffold's exact-inventory
   check, and the copy is deleted in a `finally` block.
4. Is enforced at the only mutation point: `Invoke-LzScaffold -Apply`
   classifies the report as `pass`/`fail`/`missing`/`stale` before
   `Copy-LzScaffoldTree`, records the outcome in `scaffold-audit.json`
   (`validation = @{ reportPath; status; manifestSha256Match; overridden }`),
   and throws with the remediation ("run `./validate-render.ps1` and re-run
   the scaffold") unless `LZ_SCAFFOLD_ALLOW_UNVALIDATED=true` records a loud,
   audited override.

## Alternatives considered

- **Validate inside the renderer.** Rejected: the renderer is deliberately
  network-free and fast — it must run inside the wizard/render loop and in
  Factory CI without registry access. `terraform init` needs the provider
  registry, and a security scanner can take minutes; coupling them to every
  render would break the renderer's contract and slow the feedback loop it
  exists to provide.
- **Validate only in the generated repository's CI.** Rejected: the generated
  repo's own checks run *after* the scaffold has committed and pushed the
  tree, but the requirement is that no undeployable or non-compliant artifact
  is ever **committed** to the customer repository. Post-commit detection
  leaves the defect in the customer's history and on their default branch or
  PR. The generated CI remains as defense in depth, not as the gate.

## Consequences

- **Terraform and network access are needed at validate time.** V03 proves
  every module source and provider constraint resolves, which requires the
  registry. A missing `terraform` binary fails V02–V04 closed (remediation:
  install per the `factory-version.json` toolchain contract) rather than
  skipping silently.
- **Optional tools skip openly, and `-Strict` closes the gap.** tflint and the
  scanners are not part of the required toolchain, so their absence records an
  explicit `skipped` gate with a WARN remediation — evidence, not an omission
  (the Factory CI skip convention). `-Strict` / `LZ_VALIDATE_STRICT=true`
  converts a missing optional tool into a failure for engagement runs, and
  `-SkipLint` / `-SkipSecurityScan` record deliberate operator skips.
- **The override is an approved-exception path, mirroring `-AllowNotReady`.**
  `LZ_SCAFFOLD_ALLOW_UNVALIDATED=true` exists for the same reason the broker's
  `-AllowNotReady` does: an accountable, documented exception — it warns
  loudly and is recorded (`overridden = true`) in `scaffold-audit.json`, so an
  unvalidated publication can never be silent.
- **Evidence is render-bound.** A report whose `manifestSha256` does not match
  the current `render-manifest.json` is `stale` and rejected: re-rendering
  invalidates prior validation by construction, so evidence cannot be reused
  across renders.
