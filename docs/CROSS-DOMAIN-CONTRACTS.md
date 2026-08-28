# Cross-Domain Contracts

> **Reconciled 2026-08-28 against the post-refactor codebase.** Every contract
> below was re-verified file by file. Four are **VOID** — contracts #5, #8 and
> #9 named bespoke Terraform modules that
> [ADR 0013](decisions/0013-generator-only-avm-architecture.md) deleted, and
> #6's lock-file policy was superseded. Their headings are retained, marked,
> and **not renumbered**, because contract numbers are cited by number in live
> code (`factory/bootstrap/LZFactory.Bootstrap.psm1`,
> `scripts/Start-LandingZoneBootstrap.ps1`) and asserted in
> `factory/tests/Test-Bootstrap.ps1`. Renumbering would silently break those
> citations.
>
> **Live contracts: #1, #2, #3, #4, #7.**

**Purpose**: This is a reference of the load-bearing contracts that span more than
one domain (schema, wizard, factory templates, Terraform, CI). Each entry lists
every file that participates. If you edit **one** side of a contract, you must
check — and usually change — the other sides. (This previously said to dispatch
through `alz-orchestrator`; that agent was removed with the repo-local
orchestration config — [ADR 0021](decisions/0021-orchestration-config-moves-to-workspace.md).
The obligation is unchanged: do not edit one side in isolation.)

**Provenance**: entries were first verified against the repo on 2026-08-06 and
revised through 2026-08-10 as contracts #8 and #9 were added. The whole file was
re-verified file by file on **2026-08-28** against the post-refactor codebase;
each contract now carries its own correction note where its text changed.

---

## 1. `org_prefix` pattern: `^[a-z0-9]{2,10}$`

The organization short-name / prefix pattern must be byte-identical everywhere it
appears.

| File | Where |
| --- | --- |
| `factory/schema/lz-config.schema.json` | `organization.companyShortName` pattern |
| `site/app.js` | `RE.shortName` regex and its error message |
| `site/index.html` | Field hint text and `maxlength` |
| `factory/templates/terraform/live/platform-management/variables.tf` | `org_prefix` validation |
| `factory/templates/terraform/live/platform-connectivity/variables.tf` | `org_prefix` validation |
| `factory/templates/terraform/live/state-hardening/variables.tf` | `org_prefix` validation |
| `factory/tests/Test-Renderer.ps1` | Asserts the expected pattern |

**Corrected 2026-08-28.** The table previously listed
`factory/templates/terraform/live/global/variables.tf` — that layer declares no
`org_prefix` — and two `terraform/live/*` paths from the deleted bespoke tree.
The `state-hardening` layer was missing. Verified by grep across every emitted
layer.

The old **"Known gap"** note here is **void**: it warned that the drift check
only covers `factory/templates/` while `terraform/live/` was synced by hand.
There is no second tree any more, so `Test-LzSchemaDrift` covers the whole
surface.

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
and the **emitted** workflows in the generated repository —
`factory/templates/.github/workflows/terraform-plan.yml.tmpl`,
`terraform-apply.yml.tmpl` (read-only gate job),
`terraform-fmt-validate.yml.tmpl`, and `azure-auth-test.yml.tmpl`.

> **Reconciled 2026-08-26.** This span list previously named
> `.github/workflows/010-terraform-init.yml` and `020-rbac-validation.yml`
> in *this* repository. Both were deleted with the self-deploying tree by
> [ADR 0013](decisions/0013-generator-only-avm-architecture.md): the factory
> no longer deploys anything itself, so the contract is now honoured by the
> workflows it **emits** into each generated repository, not by workflows
> here. The rule below is unchanged — it is the privilege split that
> matters, wherever the jobs run.

**Rule**: any job that is read-only — every `pull_request` trigger, and any
push/schedule/dispatch job without an `environment:` — must authenticate as
`AZURE_PLAN_CLIENT_ID`. The apply SP can only be assumed from an
environment-gated job. Giving the `pull_request` subject (or any branch
subject) to the apply SP breaks the privilege split.

## 3. AAD-only state access

The state storage account is created with shared keys disabled. Consequently:

- every azurerm `backend.hcl` needs `use_azuread_auth = true`;
- every `terraform_remote_state` data source needs `use_azuread_auth = true`;
- any provider block that manages storage containers needs
  `storage_use_azuread = true`.

**Spans** (re-verified 2026-08-28):

| File | Role |
| --- | --- |
| `factory/bootstrap/LZFactory.Bootstrap.psm1` | `Set-LzAzurermBackend` creates the account with `--allow-shared-key-access false` and `--allow-blob-public-access false`; the comment there cites this contract by number |
| `factory/templates/terraform/live/_layer/backend.hcl.tmpl` | Emits `use_azuread_auth = true` into every generated layer's backend |
| `scripts/Start-LandingZoneBootstrap.ps1` | Cites this contract when explaining why key auth is unavailable |
| `site/app.js` | The `backendHcl` generator |

The broker also grants the state data-plane roles when the backend is azurerm —
plan → Storage Blob Data Reader, apply → Storage Blob Data Contributor. A new
root stack, a new remote-state read, or a change to the wizard's backend output
must carry the flag or `terraform init` fails to authenticate.

**Corrected 2026-08-28.** The previous span list named `scripts/New-BackendConfig.ps1`
(deleted), `terraform/backend-bootstrap/`, all `terraform/live/*/backend.hcl`, and
the `workloads-{prod,nonprod}` corpus templates — none of which exist. The
closing note about live and corpus state-container layouts being "deliberately
different" is also void: there is only one layout now, the emitted one, with a
shared container and per-layer keys. Hardening posture: [ADR 0019](decisions/0019-state-storage-hardening.md).

## 4. Deliberately unmapped variables

Two variables are **intentionally not collected by the wizard**. The omission is
the contract — do not "fix" it by adding schema keys or wizard fields.

- **`management_ip_ranges`** — operator-supplied, required, wildcard-rejecting.
  The rendered connectivity tfvars carries a **commented placeholder** the
  operator uncomments; `*` and `0.0.0.0/0` are rejected. The broker detects and
  explains an unfilled placeholder but never edits it and never blocks — see
  `Test-LzFirstApplyPreflight` in `factory/bootstrap/LZFactory.Bootstrap.psm1`,
  whose remediation text cites this contract by number.
- **`log_analytics_workspace_id`** — owned by the platform-management layer and
  deliberately absent from the schema and the wizard; the workspace never flows
  through `lz-config.json`. It is exported by
  `factory/templates/terraform/live/platform-management/outputs.tf.tmpl` and
  consumed downstream.

**Spans**: `factory/bootstrap/LZFactory.Bootstrap.psm1` (detection and
remediation text), `site/app.js` (emits the commented operator placeholders),
`factory/templates/terraform/live/platform-management/outputs.tf.tmpl`.

**Corrected 2026-08-28.** The previous text described the workspace ID as
reached through a `count`-gated remote-state read named
`wire_management_workspace`, defaulting to `false` and flipped by PR after the
management layer's first apply, with a `management_workspace` re-export feeding
`nsg-flow-logs` from the connectivity remote state. **All of that machinery is
gone** — `wire_management_workspace` appears nowhere in the repository, and
`nsg-flow-logs` was deleted with the bespoke module tree
([ADR 0013](decisions/0013-generator-only-avm-architecture.md)). The closing
note about `security.nsgFlowLogs.*` mappings is void for the same reason. What
survives is the contract's actual point: **neither variable is wizard-collected,
and neither should become so.**

## 5. `spoke-network` provider alias — ⊘ VOID

The `spoke-network` module was deleted by
[ADR 0013](decisions/0013-generator-only-avm-architecture.md); confirmed absent
2026-08-28. Nothing declares this alias. Heading retained unrenumbered so the
contract numbers cited in code keep their meaning.

## 6. Lock-file policy — ⊘ SUPERSEDED

The old rule placed `.terraform.lock.hcl` at root stacks
(`terraform/backend-bootstrap/`, each `terraform/live/*/`) and forbade it in
`terraform/modules/*`. **None of those paths exist.**

Current policy, verified 2026-08-28: the emitted corpus commits **no** lock
files at all — `.gitignore` line 32 excludes
`factory/templates/**/.terraform.lock.hcl`, and a find across
`factory/templates` returns zero. Lock files are generated by `terraform init`
inside the **generated** repository, where Renovate owns the AVM pins from
delivery onward ([ADR 0013](decisions/0013-generator-only-avm-architecture.md)).

## 7. Validation-bounds ordering: wizard ⊂ schema ⊂ terraform

Validation bounds may only widen left-to-right: the wizard may be stricter than
the schema, and the schema stricter than Terraform — never the reverse. A value
the wizard accepts must be accepted by the schema and by Terraform.
`Test-LzSchemaDrift` blocks on a violation and prints a counterexample.

## 8. `nsg-flow-logs` storage names must be distinct, and the gate renders `false` — ⊘ VOID

The `nsg-flow-logs` module was deleted by
[ADR 0013](decisions/0013-generator-only-avm-architecture.md); confirmed absent
2026-08-28, and `enable_nsg_flow_logs` no longer appears in
`factory/renderer/variable-map.json`. Both invariants this contract carried are
moot. The costing analysis and the unverified per-GB rates survive in
[decision 0009](decisions/0009-nsg-flow-log-scope-and-workspace-target.md),
where the standing prohibition on quoting those figures as prices still
applies. Heading retained unrenumbered.

## 9. The blob private DNS zone is owned by connectivity and consumed by the workload layers — ⊘ VOID

Every module this contract coordinated — `hub-network`, `spoke-network`,
`nsg-flow-logs` — and the `workloads-{prod,nonprod}` layers that consumed the
exported zone were deleted by
[ADR 0013](decisions/0013-generator-only-avm-architecture.md); all confirmed
absent 2026-08-28. Workload spokes are per-estate work in the generated
repository ([ADR 0017](decisions/0017-wizard-scope-vs-emitted-architecture.md)),
not generator layers, so there is no cross-layer ownership left to coordinate.
Heading retained unrenumbered.

## How to validate

After touching any side of a contract, run:

```bash
node factory/tests/test.js
pwsh -File factory/tests/Test-Renderer.ps1
pwsh -File factory/ci/Invoke-FactoryCI.ps1   # full suite; ShellCheck is CI-runner-only
```

Factory CI renders both topology fixtures and runs `terraform fmt`, `init` and
`validate` against the **rendered output** — that is where the emitted Terraform
is checked, since this repository contains no root stacks of its own.

**Corrected 2026-08-28.** This section previously ended with
`terraform fmt -check -recursive terraform/` and told you to run
`terraform validate` in `terraform/backend-bootstrap/` and each
`terraform/live/*/`. That tree was deleted by
[ADR 0013](decisions/0013-generator-only-avm-architecture.md); those commands
now fail with "no such file or directory".
