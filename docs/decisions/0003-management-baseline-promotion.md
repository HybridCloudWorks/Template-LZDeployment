# Decision 0003 — Promoting `management-baseline` into the corpus platform-management layer (WP4)

**Date**: 2026-08-02
**Status**: Accepted — **IMPLEMENTED 2026-08-02** (WP4 of
[docs/plans/corpus-live-reconciliation.md](../plans/corpus-live-reconciliation.md);
execution recorded in CHANGELOG.md "Corpus↔live reconciliation executed").
The status line originally read "NOT IMPLEMENTED"; corrected 2026-08-07 during
the docs staleness review — the corpus platform-management layer carries the
`management_baseline` call, variables, and workspace output.
**Design authority**: `azure-platform-architect`, 2026-08-02

## Context

The corpus `platform-management` layer never calls
`module "management_baseline"` — finding (a) of the reconciliation plan.
Verified 2026-08-02: `factory/templates/terraform/live/platform-management/main.tf.tmpl`
declares only `module "backup_primary"` and `module "backup_dr"`; its
`variables.tf` lacks `org_prefix`, `log_retention_days`, and
`alert_email_receivers`; its `outputs.tf.tmpl` lacks the
`log_analytics_workspace_id` export that live
`terraform/live/platform-management/outputs.tf:1-4` provides. Every generated
repo therefore ships with **no central Log Analytics workspace**, while the
corpus connectivity layer documents that value as platform-management-owned.

Closing the gap requires deciding where three variable values come from, and
how the connectivity layer consumes the resulting workspace ID.

## Decision A — `log_retention_days`

Map the **existing** schema key `observability.logAnalytics.retentionDays`
(`factory/schema/lz-config.schema.json:673` — integer, minimum 30, maximum
730, default 90). **No new schema key.**

Bounds nest correctly: schema 30–730 ⊂ Terraform 7–730 (live
`terraform/modules/management-baseline/variables.tf:24`), so
`Test-LzSchemaDrift` needs no bound edits and contract #7's
wizard ⊂ schema ⊂ Terraform ordering holds. Retention is a genuine client
compliance decision, so it is wizard-worthy; the wizard may lag the schema
(contract #7 permits wizard ⊂ schema).

## Decision B — `alert_email_receivers`

Compose the `list(object({ name, email_address }))` from the existing
`observability.alerting.actionGroupEmails`
(`factory/schema/lz-config.schema.json:697`). Default `[]` when absent — the
action group still renders, alerts route nowhere, and the generated
observability doc should flag that.

**Explicitly rejected**: defaulting from `operations.platformTeam.contacts`
(schema `:728`) or `operations.breakGlassContacts` (schema `:754`). Those
emails were collected for **generated runbook contact tables**, not for Azure
Monitor enrollment — the schema says so itself for the sibling phone field:
*"Used only in generated runbook contact tables. Never transmitted."*
(`:71`). Silently subscribing them would transmit personal contact data into
an Azure resource and mail people who never opted in. **Notification
enrollment must be an explicit act.**

A wizard "copy platform-team contacts" prefill **button** that writes into
`actionGroupEmails` is acceptable — consent stays explicit, and it is
recorded in the exported config.

## Decision C — retire the manual loop-back

Today the operator applies platform-management, opens its outputs, copies a
~200-character resource ID, and pastes it into the connectivity tfvars — per
layer. Replace that with a **pre-rendered, `count`-gated
`terraform_remote_state` read** of platform-management in the corpus
connectivity layer, controlled by a new corpus boolean
`wire_management_workspace` (default `false`), carrying `use_azuread_auth`
from the config (contract #3) and the correct HCP workspace name.

**Why the gate is mandatory**: the generated plan workflow plans *every*
rendered layer on every PR, while applies are manual per-layer dispatch. An
ungated remote-state read would make the **first PR in every generated repo
fail red**, because platform-management has not been applied yet. And
`try()` cannot rescue it — `try()` guards expression evaluation, not provider
reads. Only `count` works.

Operator action shrinks from the copy-paste dance to **flipping one boolean
in a PR**.

**Rejected alternative**: render-time prediction of the deterministic
workspace name (`law-{org_prefix}-{region_code}`). Zero manual steps, but it
couples the connectivity layer to the module's naming internals — a hidden
contract that breaks silently on rename.

## Decision D — variable-map additions (planned)

- `layers.platform-management.variables`: `org_prefix → organization.companyShortName`,
  `log_retention_days → observability.logAnalytics.retentionDays`,
  `alert_email_receivers → computed.alertEmailReceivers`.
- `layers.platform-connectivity`: `wire_management_workspace → literal:false`,
  plus the three `state_*` variables the azurerm remote-state variant needs
  (mirroring the existing `workloads-prod` pattern).

## Decision E — implementation spec

- The `management_baseline` module call is added **unconditionally** to
  `main.tf.tmpl` — a central workspace is the layer's reason to exist; do not
  gate it behind a feature toggle. Mirror live
  `terraform/live/platform-management/main.tf:29-38`; all six arguments are
  plain `var`/`local` references, so **no tokenization is needed**.
- Copy the three variables from live `variables.tf:6-36`, including the
  byte-identical contract-#1 `^[a-z0-9]{2,10}$` regex on `org_prefix`. This
  makes the corpus `platform-management/variables.tf` a **new row in contract
  #1's table** (see the amendment note below — planned, not yet added).
- Add the `log_analytics_workspace_id` output unconditionally.
- Add tfvars template entries with `#{{IF defined …}}` gates.
- **Prerequisite**: sync the stale corpus `management-baseline` module first
  (add `alert_email_receivers` and the `dynamic "email_receiver"` block —
  WP2). Without it, the new layer call fails `terraform validate` on an
  unknown module argument.

## Planned contract amendments

Recorded here rather than applied to
[docs/CROSS-DOMAIN-CONTRACTS.md](../CROSS-DOMAIN-CONTRACTS.md),
because that file must stay truthful about the **current** tree and none of
this is implemented. The contract file carries only a one-line pointer to
this record. Apply these edits **as part of WP4**, not before:

**Contract #4 — `log_analytics_workspace_id`.** Keep the entry and
`management_ip_ranges` exactly as they are. For `log_analytics_workspace_id`,
record that:

- it remains **deliberately absent from the schema and the wizard** — the
  workspace is platform-management-owned and never flows through
  `lz-config.json`; the omission is still the contract;
- the generated connectivity layer now carries a **pre-rendered `count`-gated
  remote-state read** (`wire_management_workspace`, default `false`), flipped
  after platform-management's first apply;
- the **manual resource-ID paste is retired**.

**Contract #1 — pattern table.** Add a row for
`factory/templates/terraform/live/platform-management/variables.tf`
(`org_prefix` validation) once WP4 adds that variable.
