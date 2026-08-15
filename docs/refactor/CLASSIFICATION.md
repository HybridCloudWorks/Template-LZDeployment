# Refactor gate 1 — Classification of the repository tree

Generator-only refactor (operator-directed 2026-08-15, superseding the vendored-corpus
model). Every top-level directory, root script, and workflow is classified into exactly
one of **KEEP** (website + generator tooling), **CONVERT-TO-GENERATOR-TEMPLATE**
(content that must become an emitted output template), or **DELETE** (architecture that
must not live in Repo A). Unresolvable items are listed under **UNRESOLVED** — nothing
here is guessed.

Classification base: branch `claude/repo-alignment-review-5ita4y`, 1,355 tracked files.

## Top-level directories

| Path | Classification | Rationale |
| --- | --- | --- |
| `site/` | **KEEP** | The Q&A wizard — the product. Zero-network (CSP + CI-enforced), exports `lz-config.json` v2.0.0. Aligned in place: backend step becomes azurerm-only; Virtual WAN export unblocks (Phase 6). |
| `factory/renderer/` | **KEEP** | Render orchestration, token engine, manifest, variable map. Retargeted to the AVM corpus (Phase 2); the `directories` verbatim module-copy path is retired. |
| `factory/validate/` | **KEEP** | Fail-closed gates V01–V08 — retained and retargeted; exceeds the refactor's own task-4 requirement. |
| `factory/scaffold/` | **KEEP** | Push-or-PR delivery with SHA-bound validation refusal. Gains a non-interactive GitHub App/PAT auth path (Phase 5). |
| `factory/bootstrap/` | **KEEP** | Repo B hardening broker (environments, rulesets, OIDC variables, federated credentials, read-back). Gains branch-ref/PR federated subjects + container-scope state RBAC (Phase 5). Absorbs state-storage bootstrap from the deleted `terraform/backend-bootstrap/` tree. |
| `factory/discovery/`, `factory/ci/`, `factory/release/`, `factory/tests/`, `factory/schema/` | **KEEP** | Generator tooling. De-TFC'd (Phase 4); CI checks retargeted off the deleted live tree (Phase 3); fixtures rebuilt azurerm-only. |
| `factory/templates/` | **KEEP (contents rebuilt)** | The template corpus location. The vendored `terraform/modules/**` mirror and per-layer bespoke live templates are **replaced** by AVM-referencing root-module templates (Phase 2). |
| `terraform/` | **DELETE** | Working architecture in Repo A: 11 bespoke modules (~3,958 HCL lines), 5 self-deploying live layers, `backend-bootstrap/`. The generator emits root modules referencing AVM by pinned registry source+version; module source is never vendored. `backend-bootstrap`'s *concern* (state RG/storage/containers) moves to the broker as `az` CLI provisioning — see UNRESOLVED-1 for the mechanism decision. |
| `frontend/` | **KEEP** | Operator direction: items flagged "honestly better/keep" are improved, not removed. It is a legacy strict subset of `site/`; its landing page gains an explicit deprecation banner pointing at `site/` (Phase 6). It no longer targets an in-repo live tree (that tree is deleted), which makes its historical role documentation-only. |
| `functions/` | **DELETE** | Dead code, not generator tooling: no Functions host scaffolding (`host.json`/`function.json` absent), hardcoded sample data (`functions/run.ps1:36-58`), unreferenced repo-wide. The refactor prompt's KEEP list assumed these were live tooling; they are not, and keeping dead endpoints in a client-copied generator is a liability. |
| `cli/` | **DELETE** | REST client for the deleted `functions/` API, hardcoded to `https://alz-api.azurewebsites.net` (`cli/ALZ-Management.psm1:16-19`), zero references. Same rationale as `functions/`. |
| `dashboards/`, `runbooks/` | **KEEP** | Operator-facing collateral; no architecture. Reviewed for stale live-tree references in Phase 8. |
| `docs/` | **KEEP** | Decision records, contracts, runbooks. ADRs updated per new requirements (Phase 8); `docs/refactor/` gate documents added. |
| `scripts/` | **KEEP** | Generator/broker entry points. `Start-LandingZoneBootstrap.ps1` loses its Terraform Cloud phase (Phase 4); `Initialize-ClientFork.ps1` remains the private-copy mechanic per decision 0007. |
| `.github/` | **KEEP (pruned)** | Factory CI stays. Landing-zone deploy workflows that operate on the deleted live tree are removed — see workflow table. |
| `.azure/`, `.claude/`, `.mcp.json` | **KEEP** | Tooling configuration only (decision 0008). |

## Root scripts

| Script (`.ps1` + `.sh`) | Classification | Rationale |
| --- | --- | --- |
| `validate-render` | **KEEP** | Wraps the retained validation gates. |
| `scaffold-copy` | **KEEP** | Delivery entry point; its claim of writing `factory-version.json` into Repo B becomes true in Phase 2 (stamp is now actually emitted). |
| `bootstrap-broker` | **KEEP** | Repo B hardening entry point; gains App/PAT path. |
| `release-readiness` | **KEEP (reworked)** | Evidence binding retargets from the dogfood live estate to the end-to-end generation proof (Phase 3/9). |
| `dogfood-instance` | **DELETE** | Drives render→plan→apply of the in-repo live estate, which no longer exists. Replaced by the Phase 9 end-to-end generation proof (wizard-driven, headless). |
| `brownfield-import` | **UNRESOLVED** (retained, quarantined) | See UNRESOLVED-2. |

## Workflows (`.github/workflows/`)

| Workflow | Classification | Rationale |
| --- | --- | --- |
| `factory-ci.yml` | **KEEP (retargeted)** | Canonical generator CI; live-tree checks removed, corpus checks retargeted. |
| `action-pinning-policy.yml` | **KEEP** | Enforces 40-char SHA pins over both Repo A workflows and emitted templates. |
| `secrets-scan.yml` | **KEEP** | TruffleHog + CodeQL. |
| `deploy-pages.yml` | **KEEP** | Publishes `site/` (+ `frontend/`) — the hosted wizard. |
| `release-readiness.yml` | **KEEP (reworked)** | Binds e2e generation evidence instead of dogfood plan/apply evidence. |
| `terraform-policy-checks.yml` | **KEEP (retargeted)** | fmt/validate now runs against the emitted-output fixture render, not `terraform/live`. |
| `010-terraform-init.yml` | **DELETE** | Initializes the deleted live estate. |
| `020-rbac-validation.yml` | **DELETE** | Audits the deleted live estate's identities. |
| `terraform-plan.yml` | **DELETE** (as a Repo A workflow) | Plans `terraform/**` here. The **emitted template** `factory/templates/.github/workflows/terraform-plan.yml.tmpl` is the surviving artifact of this intent — already CONVERT-ed. |
| `terraform-apply.yml` | **DELETE** (as a Repo A workflow) | Same; emitted `terraform-apply.yml.tmpl` survives. |
| `azure-auth-test.yml` | **DELETE** (as a Repo A workflow) | OIDC smoke-test of this repo's own deploy identities, which are retired with the live estate; emitted `azure-auth-test.yml.tmpl` survives. |
| `dogfood-instance.yml` | **DELETE** | Renders and applies the dogfood estate; carries the last workflow TFC remnant (`TF_API_TOKEN` at lines 121, 177). |

## CONVERT-TO-GENERATOR-TEMPLATE (net-new emitted artifacts)

Content that previously existed as working config in Repo A (or not at all) and must
exist only as emitted output templates after this refactor:

| Emitted artifact | Source of truth before | After |
| --- | --- | --- |
| `terraform/live/global` root module → `Azure/avm-ptn-alz/azurerm` @ 0.21.0 | `terraform/modules/{management-groups,policy-baseline}` (bespoke) | Template only |
| `terraform/live/platform-management` root module → `Azure/avm-ptn-alz-management/azurerm` @ 0.9.0 | `terraform/modules/{management-baseline,backup-baseline}` (bespoke) | Template only |
| `terraform/live/platform-connectivity` root module → `Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm` @ 0.17.3 **or** `Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm` @ 0.17.1, per topology answer, never both | `terraform/modules/{hub-network,nsg-flow-logs}` (bespoke, hub-and-spoke only) | Template only |
| Per-layer `backend.tf` (empty `azurerm` block) + `backend.hcl` (`use_oidc = true`, `use_azuread_auth = true`) | Inline-rendered `backend.tf` with hardcoded values; `backend.hcl` existed only in the (deleted) live tree | Template only |
| `.gitignore` (with `.alzlib/`) | Did not exist in emitted output | Template only |
| `renovate.json` | Did not exist anywhere | Template only |
| `lz-config.json` answer record + `factory-version.json` stamp committed into Repo B | Downloadable from wizard only; stamp claim was false | Emitted by manifest |

## DELETE consequences accepted and recorded

The four-pin AVM architecture does not carry every capability of the bespoke corpus.
The following are **dropped from emitted output** (recorded in ADR 0017; the wizard
answers that fed them remain in the answer record and generated documentation only):

- Third-party NVA firewall option (`palo`/`fortinet`) — AVM connectivity patterns
  deploy Azure Firewall; the wizard choice narrows to `azfw` + tier.
- Bespoke `nsg-flow-logs`, `backup-baseline`, `defender-baseline` modules — Defender
  and logging posture now flows through ALZ policy archetypes and the management
  pattern module, not hand-written resources.
- `workloads-prod` / `workloads-nonprod` spoke layers and `sandbox` layer — workload
  spokes are per-estate work in Repo B, not generator architecture (consistent with
  the existing `REVIEW.md:196` position).
- The 12 hand-authored policy definitions / 8 assignments — replaced by the ALZ
  library (`platform/alz` @ `2026.04.2`) via the `alz` provider.

## UNRESOLVED

1. **State-storage bootstrap mechanism.** `terraform/backend-bootstrap/` (working TF
   that created the state RG/storage/containers with RAGZRS, AAD-only auth, optional
   private endpoint) is deleted. The broker (`LZFactory.Bootstrap.psm1`) already
   provisions identity/RBAC via `az`; Phase 5 extends it to create the state
   RG/storage-account/containers. Whether the private-endpoint/private-DNS option of
   the old bootstrap must be preserved in the broker is an operator call — not
   implemented in this pass, recorded here rather than guessed.
2. **`brownfield-import`.** Its import-block generation targets the deleted bespoke
   modules' resource addresses. Rewriting it against AVM pattern-module internal
   addresses cannot be verified without registry access (blocked in this environment,
   HTTP 403). The scripts are retained but their entry points now refuse with a
   pointer to this record until re-targeted.
3. **`avm-ptn-alz-management` exact input surface at 0.9.0** and **connectivity module
   input surfaces at 0.17.x** could not be re-verified against the Terraform Registry
   from this environment (proxy 403). Emitted root modules follow the modules'
   documented interfaces; `terraform init && terraform validate` on generated output
   is the execution-time proof (VALIDATION.md records the exact commands and the
   environment limitation).
