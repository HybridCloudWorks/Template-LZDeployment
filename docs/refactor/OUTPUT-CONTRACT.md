# Refactor gate 3 — Output contract

The machine-readable output contract **is**
[`factory/renderer/template-manifest.json`](../../factory/renderer/template-manifest.json)
(manifestVersion 2.0.0). This document explains how it is enforced; the manifest
itself is the single source of truth for what the generator emits into Repo B.

## Fail-closed enforcement

- **Produced file not on the manifest → FAIL.** Validation gate **V01
  inventory-integrity** (`factory/validate/LZFactory.Validate.psm1`) compares the
  rendered tree against `render-manifest.json` (the per-render record of manifest
  evaluation) and fails on any extra, missing, or duplicate file, and on any
  rooted/path-traversal destination.
- **Manifest file missing → FAIL.** The renderer throws when a manifest entry's
  source template does not exist; V01 fails when a declared destination was not
  produced.
- **Orphaned template → FAIL.** `factory/ci/Test-TemplateCoverage.ps1` (Factory
  CI check "Template coverage") fails when a file exists under
  `factory/templates/` that no manifest entry references, in either direction.
- **Scaffold refusal.** The scaffold builder refuses to publish a tree whose
  `validate-report.json` does not hash-match the render (SHA-256-bound), so an
  unvalidated or stale render can never reach Repo B.

## What is emitted (summary; the manifest is authoritative)

| Group | Files |
| --- | --- |
| Root | `README.md`, `USER-CHECKLIST.md`, `.gitignore` (with `.alzlib/`), `renovate.json`, `lz-config.json` (answer record), `factory-version.json` (generator version stamp) |
| Terraform | Three root-module layers (`platform-management`, `global`, `platform-connectivity`†) — each `main.tf` referencing Azure Verified Modules by pinned registry source+version, `variables.tf`, `outputs.tf`, `terraform.auto.tfvars`, empty-block `backend.tf`, and `backend.hcl` (`use_oidc`, `use_azuread_auth`) |
| Workflows | 7 SHA-pinned workflows: plan, fmt-validate, apply, action-pinning-policy, security-scan, policy-diff-guardrails, azure-auth-test |
| Docs | 10 generated operational documents (identity trust matrix, governance, threat model, observability, finops, state management, DR, operating model, upgrade guide, phase model) |

† Omitted entirely when `connectivity.model = none`. Exactly one topology module
is emitted (hub-and-spoke `0.17.3` **or** Virtual WAN `0.17.1`), never both.

## What is never emitted

No generator machinery: no website, no PowerShell tooling, no `factory/`, no
`node_modules`, no functions host, no module source. The manifest contains no
`directories` mechanism any more — the former whole-tree module copy was retired
with the vendored corpus (ADR 0013). The Phase-9 proof additionally asserts zero
generator files in the output tree.

## AVM pins the emitted root modules use

| Module | Source | Version |
| --- | --- | --- |
| ALZ core (MGs + policy) | `Azure/avm-ptn-alz/azurerm` | 0.21.0 |
| Management | `Azure/avm-ptn-alz-management/azurerm` | 0.9.0 |
| Connectivity (hub-and-spoke) | `Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm` | 0.17.3 |
| Connectivity (Virtual WAN) | `Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm` | 0.17.1 |

Providers: `Azure/alz ~> 0.21.0`, `Azure/azapi ~> 2.12`,
`hashicorp/azurerm ~> 4.0`. ALZ library: `platform/alz @ 2026.04.2` via the
`alz` provider's `library_references`. These set the **initial** pins only:
Renovate (emitted `renovate.json`) owns them inside Repo B forever, with no
dependency on this factory. All pattern modules are major-version-zero; every
pin is re-verified at execution time by `terraform init` (Factory CI runs this
on rendered fixtures; the generated repo's first init re-verifies on delivery).
