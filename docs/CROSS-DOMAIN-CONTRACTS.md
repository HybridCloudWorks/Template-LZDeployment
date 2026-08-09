# Cross-Domain Contracts

**Purpose**: This is a reference of the load-bearing contracts that span more than
one domain (schema, wizard, factory templates, Terraform, CI). Each entry lists
every file that participates. If you edit **one** side of a contract, you must
check — and usually change — the other sides, or dispatch the change through
`alz-orchestrator` so no side is edited in isolation.

All entries verified against the repo on 2026-08-06; contract #4 corrected and
contract #8 added 2026-08-09 (decision 0009).

---

## 1. `org_prefix` pattern: `^[a-z0-9]{2,10}$`

The organization short-name / prefix pattern must be byte-identical everywhere it
appears.

| File | Where |
| --- | --- |
| `factory/schema/lz-config.schema.json` | `organization.companyShortName` pattern |
| `site/app.js` | `RE.shortName` regex and its error message |
| `site/index.html` | Field hint text and `maxlength` |
| `factory/templates/terraform/live/global/variables.tf` | `org_prefix` validation |
| `terraform/live/global/variables.tf` | `org_prefix` validation |
| `terraform/live/platform-management/variables.tf` | `org_prefix` validation |
| `factory/templates/terraform/live/platform-management/variables.tf` | `org_prefix` validation |
| `factory/tests/Test-Renderer.ps1` | Asserts the expected pattern |

**Known gap**: the renderer drift check (`Test-LzSchemaDrift`) only compares the
schema against `factory/templates/`. The `terraform/live/` copies are synced **by
hand** until the repo is regenerated from the factory (Stage 13). Changing the
pattern in the schema does not fail CI if `terraform/live/` is left stale — check
it yourself.

## 2. OIDC identity split (plan SP vs apply SP)

Two service principals, strictly separated by OIDC subject (subject table
updated 2026-08-02 — `ref:refs/heads/main` moved to the plan SP because
read-only push-triggered jobs authenticate as it; the apply SP holds
environment subjects only):

| Identity | Secret | Roles | OIDC subjects |
| --- | --- | --- | --- |
| Plan SP (read-only) | `AZURE_PLAN_CLIENT_ID` | Reader @ MG root (+ Storage Blob Data Reader on the state account, azurerm) | `pull_request`, `ref:refs/heads/main` |
| Apply SP | `AZURE_CLIENT_ID` | Management Group Contributor + Resource Policy Contributor @ MG root, Contributor per distinct subscription (+ Storage Blob Data Contributor, azurerm) | `environment:<name>` only |

Read-only jobs run `terraform plan`/`init` with `-lock=false` (the plan SP
cannot take state leases).

Spans: `scripts/Start-LandingZoneBootstrap.ps1` and
`factory/bootstrap/LZFactory.Bootstrap.psm1` (create the identities and
federated credentials; `identity.cicdIdentityModel` selects minimal vs
per-environment — see
[docs/decisions/0002-minimal-identity-estate.md](decisions/0002-minimal-identity-estate.md)),
`.github/workflows/terraform-plan.yml`,
`.github/workflows/010-terraform-init.yml`,
`.github/workflows/020-rbac-validation.yml`,
`.github/workflows/terraform-apply.yml` (read-only gate job),
`.github/workflows/azure-auth-test.yml`.

**Rule**: any job that is read-only — every `pull_request` trigger, and any
push/schedule/dispatch job without an `environment:` — must authenticate as
`AZURE_PLAN_CLIENT_ID`. The apply SP can only be assumed from an
environment-gated job. Giving the `pull_request` subject (or any branch
subject) to the apply SP breaks the privilege split.

## 3. AAD-only state access

The state storage account sets `shared_access_key_enabled = false`. Consequently:

- every azurerm `backend.hcl` needs `use_azuread_auth = true`;
- every `terraform_remote_state` data source needs `use_azuread_auth = true` in
  its config;
- any provider block that manages storage containers needs
  `storage_use_azuread = true`.

Spans: `terraform/backend-bootstrap/`, all `terraform/live/*/backend.hcl`,
the remote state config in `terraform/live/workloads-prod/main.tf`, the
corpus remote-state reads in
`factory/templates/terraform/live/workloads-{prod,nonprod}/main.tf.tmpl`
(carry the flag as a rendered token since 2026-08-01), the `backendHcl`
generator in `site/app.js`, `scripts/New-BackendConfig.ps1` (generates the
per-layer `backend.hcl` files and always enforces `use_azuread_auth = true`,
overriding any source that requests key auth), and the RBAC grants in the
bootstrap script and broker — since 2026-08-02 the broker grants the state
data-plane roles itself (plan → Storage Blob Data Reader, apply → Storage
Blob Data Contributor) when the backend is azurerm, and `Set-LzAzurermBackend`
creates the state account with `--allow-shared-key-access false`. A new root
stack, a new remote-state read, or a change to the wizard's backend output
must carry the flag or authentication fails at init.

Note: the live and corpus state-container layouts are deliberately different —
live uses one container per layer with key `terraform.tfstate`; the corpus
uses a shared container with per-layer keys (`<layer>.tfstate`). Both are
internally consistent; do not "reconcile" them by editing one side.

## 4. Deliberately unmapped variables

`factory/renderer/variable-map.json` documents two variables that are
**intentionally not collected by the wizard**:

- `management_ip_ranges` — operator-supplied, required, wildcard-rejecting.
  In the corpus it maps to `literal:operator-supplied`: the rendered
  connectivity tfvars carries a commented placeholder the operator must
  uncomment, and the generated plan workflow fails fast while it is unset.
- `log_analytics_workspace_id` — owned by the platform-management stack. It
  remains **deliberately absent from the schema and the wizard** — the
  workspace never flows through `lz-config.json`. The connectivity layer
  carries a **`count`-gated remote-state read** of platform-management
  (`wire_management_workspace`, default `false`), flipped in a PR after that
  layer's first apply; an explicitly supplied variable value overrides the
  read. The **manual resource-ID paste is retired**. Rationale:
  [docs/decisions/0003-management-baseline-promotion.md](decisions/0003-management-baseline-promotion.md).

  **Corrected 2026-08-09** (decision 0009, ratified 2026-08-08): this read is
  **no longer a generated-layer-only mechanism**. It now exists in *both*
  trees — `terraform/live/platform-connectivity/main.tf` as well as
  `factory/templates/terraform/live/platform-connectivity/main.tf.tmpl` — and
  both sides re-export a `management_workspace` object (ARM id, GUID,
  location; empty strings while the gate is off). That re-export is what lets
  the workload layers feed `nsg-flow-logs` from the connectivity remote state
  they already read instead of opening a second read of platform-management.
  Editing the read or the re-export on one side without the other is a
  parity break; both are in scope of this contract.

The site's connectivity tfvars export emits commented operator placeholders for
both. Do **not** "fix" this by adding schema keys or wizard fields; the omission
is the contract — including for the flow-log wiring, whose workspace triple
comes from the remote-state read and **never** from `lz-config.json`.

Related but *not* forbidden: `security.nsgFlowLogs.retentionDays` and
`security.nsgFlowLogs.trafficAnalytics` are mapped normally in
`variable-map.json` — they configure the workspace's use, not its identity.
`security.nsgFlowLogs.enabled` is mapped `literal:false` rather than to its
config path, deliberately (see contract #8).

## 5. `spoke-network` provider alias

`terraform/modules/spoke-network` declares
`configuration_aliases = [azurerm.hub]` because hub-side peering runs in the
connectivity subscription. Every caller must pass a `providers` map — see
`terraform/live/workloads-prod/main.tf` for the reference call.

Divergence reconciled 2026-08-01: the factory template copy
(`factory/templates/terraform/modules/spoke-network/`) is at byte parity with
the live module and carries the alias. The template callers
(`factory/templates/terraform/live/workloads-{prod,nonprod}/main.tf.tmpl`)
pass `providers` maps — a dedicated `azurerm.hub` provider fed by
`connectivity_subscription_id` when a hub exists, aliased to the workload
provider when it does not. The rule stands: any new caller of this module, in
either tree, must pass a `providers` map or `terraform validate` fails.

## 6. Lock-file policy

`.terraform.lock.hcl` exists **only at root stacks**: `terraform/backend-bootstrap/`
and each `terraform/live/*/`. Module directories (`terraform/modules/*`)
deliberately carry none — do not commit lock files there, and do not delete them
from root stacks.

## 7. Validation-bounds ordering: wizard ⊂ schema ⊂ terraform

Validation bounds may only widen left-to-right: the wizard may be stricter than
the schema, and the schema stricter than Terraform — never the reverse. A value
the wizard accepts must be accepted by the schema and by Terraform.
`Test-LzSchemaDrift` blocks on a violation and prints a counterexample.

## 8. One `nsg-flow-logs` instance per `(region, environment)`, and the gate renders `false`

Two invariants that nothing in the code can enforce, so they live here.

**8a — instance ceiling.** `terraform/modules/nsg-flow-logs/main.tf` composes
the flow-log storage account name from the region code and environment with no
override. Storage account names are globally unique, so **at most one instance
of this module may exist per `(region, environment)` across the whole estate**.
A second instance in the same region and environment plans clean and then
fails at apply with a name collision — the quiet-failure shape this register
exists for.

Participants: the module's naming in both trees; every caller that decides
*how many* instances to create — `terraform/live/workloads-prod/main.tf`,
`factory/templates/terraform/live/workloads-{prod,nonprod}/main.tf.tmpl` —
and any future connectivity-hosted call.

Consequences that are live today: `workloads-prod` creates exactly two
instances, one per region; the three nonprod spokes in a region share one
instance because they share `environment = "nonprod"`; and the hub's
`fw_mgmt` NSG is **unlogged**, because covering it needs a connectivity
instance in the same region and environment as the prod one. Making the name
overridable is the prerequisite for lifting any of this
([TODO.md](../TODO.md) item 2.9).

**8b — the gate is a constant, not a wizard answer.**
`factory/renderer/variable-map.json` maps `enable_nsg_flow_logs` to
`literal:false` for both workload layers, and the rendered
`terraform.auto.tfvars` emits the constant `false`. It does **not** map
`security.nsgFlowLogs.enabled`, even though the wizard collects it and
pre-checks it. Two reasons, both load-bearing: a pre-checked box would enable
a volume-driven meter for every client who never touched it, and the module
reads `NetworkWatcher_<region>` in `NetworkWatcherRG` through the default
provider — a resource group Azure creates only with a subscription's first
VNet — so an ungated read makes the **first plan in every generated
repository** fail red. `try()` cannot rescue a provider read; only `count`
can. Same shape, same reason, as `wire_management_workspace` (contract #4).

Participants: `factory/renderer/variable-map.json`,
`factory/templates/terraform/live/workloads-{prod,nonprod}/terraform.auto.tfvars.tmpl`,
the `enable_nsg_flow_logs` variable in both workload layers' `variables.tf`,
`factory/schema/lz-config.schema.json`, `site/index.html`.

Do **not** "fix" the apparent orphan by pointing the mapping at the config
path. If the posture is ever revisited, it is a decision-record change
(0009 open question 3), not a mapping tidy-up. `factory/tests/Test-Renderer.ps1`
§15d pins both halves: the fixtures set `enabled: true` and the render must
still emit `false`.

Rationale for both:
[docs/decisions/0009-nsg-flow-log-scope-and-workspace-target.md](decisions/0009-nsg-flow-log-scope-and-workspace-target.md).

---

## How to validate

After touching any side of a contract, run:

```bash
node factory/tests/test.js
pwsh -File factory/tests/Test-Renderer.ps1
pwsh -File factory/ci/Invoke-FactoryCI.ps1   # full check suite; shellcheck is CI-runner-only
terraform fmt -check -recursive terraform/
```

and `terraform validate` in each root stack you touched
(`terraform/backend-bootstrap/`, `terraform/live/*/`).
