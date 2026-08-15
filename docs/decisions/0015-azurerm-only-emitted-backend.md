# Decision 0015 — azurerm is the only backend, everywhere

- **Status**: **Accepted** — operator-directed 2026-08-15, as part of the
  generator-only refactor
  ([decision 0013](0013-generator-only-avm-architecture.md)).
  **Supersedes the deliberate scope-out in
  [decision 0011](0011-standardize-live-tree-on-azurerm.md)** ("the
  factory's client-facing render path… dual-backend capability is a
  product feature") — that product feature is now retired.
- **Date**: 2026-08-15
- **Deciders**: operator (superseding directive, 2026-08-15); recorded by
  `docs-knowledge-curator`
- **Technical depth**: L300 (schema versions, backend arguments, removed
  surfaces)

## Context and Problem Statement

Decision 0011 standardized the (since-deleted) live tree on azurerm but
explicitly preserved the factory's **dual-backend render capability**:
`hcp-terraform` and `azurerm` were both valid `lz-config.json` backend
choices, the corpus rendered either, and the broker reconciled HCP
workspaces (`Set-LzHcpBackend`, `TFE_TOKEN`). The 2026-08-15 refactor
directive mandates **OIDC-only, Azure-native state with no third-party
state service and no static tokens** — and `TF_API_TOKEN` was the last
static credential anywhere in the system. A dual-backend product feature
cannot coexist with that mandate.

## Decision

The dual-backend feature is retired. **azurerm is the only backend
anywhere** — in the schema, the wizard, the templates, and every tooling
surface:

- **Schema 2.1.0** (`factory/schema/lz-config.schema.json`):
  `backend.type` is a `const` of `azurerm`; the schema description names
  this record. The renderer refuses any config whose `schemaVersion` it
  does not implement, so pre-2.1.0 dual-backend configs are rejected, not
  silently coerced.
- **Wizard**: the `site/` backend step is azurerm-only (state RG, storage
  account, container); no backend choice is presented.
- **Templates**: each emitted layer carries an **empty**
  `backend "azurerm" {}` block
  (`factory/templates/terraform/live/_layer/backend.tf.tmpl`) plus a
  per-layer `backend.hcl`
  (`factory/templates/terraform/live/_layer/backend.hcl.tmpl`) with
  `use_oidc = true` and `use_azuread_auth = true` — no access keys, no
  SAS tokens, and state location never hard-codes into committed
  Terraform.
- **Removed surfaces**: the TFC code paths in the token engine, render
  guards, discovery, bootstrap broker, legacy bootloader
  (`scripts/Start-LandingZoneBootstrap.ps1` — azurerm unconditionally;
  the warned hcp-terraform legacy override of decision 0011 is gone), and
  the dogfood tooling. The **Sentinel policy-engine option** — a
  Terraform Cloud feature — is removed from the schema and wizard
  (the schema records the retirement at the former enum's description).
- **The one deliberate survivor**: `scripts/Dispose-Engagement.ps1` keeps
  its `TFE_TOKEN`/`TF_API_TOKEN` sweep guidance, because disposal of
  **legacy estates** bootstrapped before this decision still has TFC
  residue to clean. That is cleanup of the past, not support for the
  feature.

## Consequences

- **Positive**: zero static credentials — state access is OIDC +
  Azure AD end to end, closing the last exception decision 0011 had
  accepted; one backend means one `backend.hcl` shape, one RBAC model
  (the broker's data-plane grants), and one init procedure to document
  and test; the schema `const` makes the invariant machine-enforced
  rather than conventional.
- **Negative**: clients who wanted HCP Terraform state lose the option —
  the operator ratified this narrowing; a future re-introduction is a new
  decision record plus a schema major bump, not a toggle.
- **Supersession mechanics**: decision 0011's *live-tree* half is
  unaffected in substance (azurerm won there too) and its tree no longer
  exists ([decision 0013](0013-generator-only-avm-architecture.md));
  only its render-path scope-out is superseded here. GitHub Issue #11
  stays resolved as "standardize, don't migrate" — this record extends
  the same answer to the product surface.
