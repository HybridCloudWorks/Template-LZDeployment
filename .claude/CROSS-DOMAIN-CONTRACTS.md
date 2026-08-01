# Cross-Domain Contracts

**Purpose**: This is a reference of the load-bearing contracts that span more than
one domain (schema, wizard, factory templates, Terraform, CI). Each entry lists
every file that participates. If you edit **one** side of a contract, you must
check — and usually change — the other sides, or dispatch the change through
`alz-orchestrator` so no side is edited in isolation.

All entries verified against the repo on 2026-08-01.

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
| `factory/tests/Test-Renderer.ps1` | Asserts the expected pattern |

**Known gap**: the renderer drift check (`Test-LzSchemaDrift`) only compares the
schema against `factory/templates/`. The `terraform/live/` copies are synced **by
hand** until the repo is regenerated from the factory (Stage 13). Changing the
pattern in the schema does not fail CI if `terraform/live/` is left stale — check
it yourself.

## 2. OIDC identity split (plan SP vs apply SP)

Two service principals, strictly separated by OIDC subject:

| Identity | Secret | Roles | OIDC subjects |
| --- | --- | --- | --- |
| Plan SP (read-only) | `AZURE_PLAN_CLIENT_ID` | Reader + Storage Blob Data Reader | `pull_request` (exclusively) |
| Contributor SP | `AZURE_CLIENT_ID` | Contributor + Storage Blob Data Contributor | `ref:refs/heads/main`, `environment:dev/prod/hub` |

PR plans run `terraform plan -lock=false` (the plan SP cannot take state leases).

Spans: `scripts/Start-LandingZoneBootstrap.ps1` (creates the federated
credentials), `.github/workflows/terraform-plan.yml`,
`.github/workflows/020-rbac-validation.yml`.

**Rule**: any new workflow that logs into Azure on a `pull_request` trigger must
use `AZURE_PLAN_CLIENT_ID`. Giving the `pull_request` subject to the Contributor
SP breaks the privilege split.

## 3. AAD-only state access

The state storage account sets `shared_access_key_enabled = false`. Consequently:

- every azurerm `backend.hcl` needs `use_azuread_auth = true`;
- every `terraform_remote_state` data source needs `use_azuread_auth = true` in
  its config;
- any provider block that manages storage containers needs
  `storage_use_azuread = true`.

Spans: `terraform/backend-bootstrap/`, all `terraform/live/*/backend.hcl`,
the remote state config in `terraform/live/workloads-prod/main.tf`, the
`backendHcl` generator in `site/app.js`, and the RBAC grants in the bootstrap
script. A new root stack, a new remote-state read, or a change to the wizard's
backend output must carry the flag or authentication fails at init.

## 4. Deliberately unmapped variables

`factory/renderer/variable-map.json` documents two variables that are
**intentionally not collected by the wizard**:

- `management_ip_ranges` — operator-supplied, required, wildcard-rejecting.
- `log_analytics_workspace_id` — owned by the platform-management stack.

The site's connectivity tfvars export emits commented operator placeholders for
both. Do **not** "fix" this by adding schema keys or wizard fields; the omission
is the contract.

## 5. `spoke-network` provider alias

`terraform/modules/spoke-network` declares
`configuration_aliases = [azurerm.hub]` because hub-side peering runs in the
connectivity subscription. Every caller must pass a `providers` map — see
`terraform/live/workloads-prod/main.tf` for the reference call.

**Known divergence**: the factory template copy
(`factory/templates/terraform/modules/spoke-network/`) does **not** yet carry the
alias. Until it does, a regeneration from the factory would drop the alias —
reconcile before Stage 13.

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

---

## How to validate

After touching any side of a contract, run:

```bash
node factory/tests/test.js
pwsh -File factory/tests/Test-Renderer.ps1
pwsh -File factory/ci/Invoke-FactoryCI.ps1   # 13 checks; shellcheck is CI-runner-only
terraform fmt -check -recursive terraform/
```

and `terraform validate` in each root stack you touched
(`terraform/backend-bootstrap/`, `terraform/live/*/`).
