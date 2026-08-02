# Plan — Corpus ↔ Live Reconciliation

**Status**: PLAN — nothing in this document is implemented.
**Audit date**: 2026-08-02 (read-only, against the tree at
[`0b758f7`](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/commit/0b758f7), post-PR #60)
**Design decisions for WP4**:
[docs/decisions/0003-management-baseline-promotion.md](../decisions/0003-management-baseline-promotion.md)
**Backlog entry**: [TODO.md](../../TODO.md) → "Reconcile live ↔ corpus drift"

> **Re-diff before executing.** Every disposition below was verified read-only
> on 2026-08-02. The trees move; treat this as the analysis of record, not as
> a current-state guarantee. Re-run the comparisons for any work package
> before starting it.

---

## Why this matters

The factory renders customer repositories from `factory/templates/`. The
`terraform/modules/**` tree is copied **verbatim as a single directory entry**
by the renderer manifest (`factory/renderer/template-manifest.json:332-333`),
so every corpus module defect lands unchanged in every generated repo. Drift
here is not cosmetic — it is shipped.

### Headline findings

**(a) The corpus `platform-management` layer never calls
`module "management_baseline"`.** Highest-impact finding. Verified:
`factory/templates/terraform/live/platform-management/main.tf.tmpl` contains
only `module "backup_primary"` and `module "backup_dr"` — no
`management_baseline` block; its `variables.tf` declares no `org_prefix`,
`log_retention_days`, or `alert_email_receivers`; its `outputs.tf.tmpl` has no
`log_analytics_workspace_id` export, which live
`terraform/live/platform-management/outputs.tf:1-4` does provide (from live
`main.tf:29-38`). **Consequence**: every generated repo ships with no central
Log Analytics workspace, while the corpus connectivity layer documents that
value as platform-management-owned. Invisible to every automated check.

**(b) Corpus workflow templates are one action generation behind live**, and
the pin checker cannot catch it. Verified pins:

| Action | Live | Corpus |
| --- | --- | --- |
| `actions/checkout` | `3d3c42e5…` v7.0.1 | `11bd7190…` v4.2.2 |
| `azure/login` | `532459ea…` v3.0.0 | `a457da9e…` v2.3.0 |
| `hashicorp/setup-terraform` | `dfe3c3f8…` v4.0.1 | `b9cd54a3…` v3.1.2 |

`factory/ci/Test-ActionPins.ps1:19` only asserts the reference matches
`@[0-9a-fA-F]{40}$` — "is a 40-hex SHA". **Pin drift can never fail CI.**

**(c) Drift is BIDIRECTIONAL — do not overwrite live with corpus.** The
corpus apply workflow is materially *safer* than live's: dispatch-only
triggering, saved-plan execution (`plan -out` then `apply tfplan`) against
live's bare `apply -auto-approve`, hard destroy refusal, trusted-ref
checkout, and root `permissions: {}`. The corpus `azure-auth-test.yml.tmpl`
enforces OIDC role assertions where live only informs. A naive corpus→live
overwrite would destroy improvements; a naive live→corpus overwrite would
destroy safety.

**(d) Every corpus module defect is shipped** — see the manifest note above.

**(e) `Test-LzSchemaDrift` is blind to almost all of this.** It compares
schema against template *variable declarations*. It does not see module
bodies, `.tmpl` content, missing module calls, provider pins, workflow
templates, action SHAs, or the `terraform/live/` tree at all. Everything in
this plan except pure variable-declaration drift is checker-invisible — which
is why WP5 adds a canonical-SHA registry, and why the platform-management gap
survived this long.

---

## Module inventory (11 modules, both trees)

| Module | Disposition |
| --- | --- |
| `spoke-network` | **In sync** — contract #5, reconciled 2026-08-01 |
| `backup-baseline`, `management-groups`, `keyvault-cmk`, `sentinel-siem`, `sandbox` | **Version-pin drift only** — corpus `~> 1.6` / azurerm `~> 4.0` vs live `>= 1.9.0` / `~> 4.2` |
| `policy-baseline` | Corpus `mode = "All"` vs live `mode = "Indexed"` on **exactly three** definitions (verified by diff), plus pins and a description |
| `management-baseline` | Corpus lacks the `alert_email_receivers` variable and the `dynamic "email_receiver"` block (live `main.tf:51-52`, `variables.tf:29`); alert still labeled `cpu_high` / named `alert-cpu-` with a stale `# CPU > 80%` comment (corpus `main.tf:54-56`) though the criteria body already matches live |
| `nsg-flow-logs` | **Live-newer throughout** — public-access model with deny-by-default network rules, `allowed_ip_cidrs` fail-closed parser, blobServices-scoped diagnostics; plus a corpus-only `next_steps` cost-guess output to drop |
| `defender-baseline` | Live rewrote to the single-subscription contract (`count` + `defender_tier` + `data.azurerm_client_config`); corpus keeps the old `for_each = var.subscriptions` map and emoji cost outputs. **Safe to sync** — no callers in either tree |
| `hub-network` | **Highest-risk sync** — see below |

### hub-network detail

Corpus still declares the duplicate `azurerm_firewall.hub_with_policy`
(verified: present only in
`factory/templates/terraform/modules/hub-network/firewall-threat-intel.tf`)
that live eliminated in favor of `firewall_policy_id` on the single
`azurerm_firewall.hub`. Corpus also keeps four outputs inline in
`firewall-threat-intel.tf` that live moved to `outputs.tf`; uses subnet
indexes 3–6 against live's documented 12–15 disjointness plan; creates an
unsupported NSG on `GatewaySubnet` that live removed; hardcodes
`nva_trust_ip_placeholder = "10.0.1.4"` where live derives a nullable local;
and exposes `output "log_analytics_workspace_id"` reading an embedded
workspace live removed.

The `management_ip_ranges` divergence is the sharpest: corpus declares
`type = string`, `default = "*"` (`variables.tf:61-65`); live declares
`type = list(string)`, required, wildcard-rejecting (`variables.tf:62-70`).
Contract #4 and the wizard both already describe the **live** shape, and the
corpus plan workflow already enforces the hardened contract — **the corpus is
internally inconsistent with itself.**

Verified: no corpus template consumes the four relocated outputs or the
embedded-workspace output, so removing them breaks nothing rendered.

> **Risk — regeneration onto existing state.** For already-generated repos,
> the subnet index move, firewall consolidation, and workspace removal are
> **destroy/recreate** plans; firewall replacement means an outage. This
> belongs in the upgrade guide and the Stage 11 brownfield path, **not** in
> the sync itself.

---

## Live-stack findings

**Deliberate — do not sync**: backend and state-container layout (contract #3
says explicitly not to reconcile these), `required_version` living in the
rendered `backend.tf`, the corpus default-empty variable pattern, and `.tmpl`
tokenization.

**Real drift**: the platform-management gap, finding (a).

**Corpus-newer — backport to LIVE**:

- `azfw_tier` "Basic" validation matching the schema enum (contract #7:
  Terraform must be at least as wide as the schema);
- the `workloads-prod` `outputs.tf.tmpl` spoke-VNet outputs — live
  `workloads-prod` has no outputs at all;
- live `terraform/live/sandbox/main.tf` pins plus expired hardcoded tag dates
  (`created_date = "2026-06-30"`, `expiry_date = "2026-07-30"`) against the
  corpus 1970 sentinel.

**One-sided exposure**: `workloads-nonprod` exists **only** in the corpus (the
live dogfood is prod-only), so it has no live counterpart to drift-check.

## Root and workflow findings

- `terraform/backend-bootstrap/` is **live-only by design** — generated repos
  get state plumbing from the broker.
- Contract #6 (lock-file policy) verified **compliant**.
- **Workflow name collisions needing an operator decision**:
  `terraform-policy-checks.yml` (live fmt/tflint/tfsec suite) vs the corpus
  `.tmpl` git-diff guardrails; `secrets-scan.yml` vs `security-scan.yml.tmpl`.
- **Live-only dead code, delete with operator approval**:
  `deploy-from-release.yml` and `generate-and-release.yml`, both hard-disabled.
- Live hardcodes Terraform `1.9.0` in three workflows where the corpus token
  resolves to the tested `1.9.8`.

---

## Work packages

Validation for **every** package: `pwsh -File factory/ci/Invoke-FactoryCI.ps1`,
`pwsh -File factory/tests/Test-Renderer.ps1`, `node factory/tests/test.js`,
`terraform fmt -check -recursive`, and `terraform validate` in each touched
root stack. End-to-end proof is an **operator-triggered dogfood render + plan**
(see [stage13-dogfood-execution.md](../runbooks/stage13-dogfood-execution.md)).

| WP | Scope | Sequencing |
| --- | --- | --- |
| **WP1** | Version-pin sweep across the corpus modules | Parallel-safe with WP2 |
| **WP2** | Small module syncs: `policy-baseline`, `management-baseline`, `nsg-flow-logs`, `defender-baseline` | Parallel-safe with WP1 |
| **WP3** | **hub-network bundle** — module + the connectivity `management_ip_ranges` / nva-trust-IP variable changes + the commented tfvars placeholder | **Indivisible.** Contracts #4 and #7 are both in play; must travel as one brief |
| **WP4** | platform-management promotion — closes finding (a) | Blocked on its design decisions, **now made** in [0003](../decisions/0003-management-baseline-promotion.md) |
| **WP5** | Workflow reconciliation: SHA bumps; corpus plan-comment/artifact parity; live adoption of the corpus safety model; **canonical-SHA registry in `Test-ActionPins`** so this drift class fails CI permanently | Items 1–2 can run parallel to WP2–WP4 |
| **WP6** | Live-side minor adoptions (the corpus-newer backports above) | After WP3 |
| **WP7** | Documentation close-out | Last |

## Execution split

**Mechanical — one `terraform-module-engineer` pass**: WP1, WP2, WP3, WP6,
and WP5 item 1.

**Decisions required before the affected work starts**:

1. **The live apply model** — push-triggered (current live) vs the corpus's
   dispatch-only. *The audit recommends dispatch-only.*
2. **Workflow renames and dead-file deletions** — operator sign-off required
   (the two collisions and the two hard-disabled files above).
3. **The management-baseline alert rename** — does it ship with a `moved`
   block, to avoid a delete/create in regenerated repos?
4. **The `workloads-nonprod` parity control** — dogfood a nonprod instance,
   or add a corpus-internal template parity check?

Cross-domain by construction: dispatch the whole reconciliation through
`alz-orchestrator` rather than editing one side of a contract at a time.
