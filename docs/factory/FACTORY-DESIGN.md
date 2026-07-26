# Azure Landing Zone Factory — Architecture & Risk Register

**Status**: Design accepted / Stages 1–13 implemented; live dogfood evidence pending
**Date**: 2026-07-24
**Scope**: Convert this repository from a single-tenant ALZ deployment into a reusable
Landing Zone Factory that emits unlimited, independent ALZ repositories across tenants,
GitHub ownership models, environments, subscriptions, and Terraform backends.

---

## 1. Executive Summary

Today this repository **is** the landing zone (README.md:5). The factory inverts that:
the repository becomes a **generator** whose output is a self-contained, self-documenting
customer repository. Nothing in the factory ever touches a customer tenant at Terraform
apply time — the factory only *bootstraps identity and repo scaffolding*, then hands off.

The product has four planes:

| Plane | Artifact | Runs where | Touches |
|---|---|---|---|
| **Config plane** | `site/` — local static wizard | Operator workstation, `file://` | Nothing. Pure client-side. |
| **Broker plane** | `bootstrap-broker.ps1` / `.sh` | Operator workstation | Entra, Azure RBAC, GitHub, HCP TFC |
| **Scaffold plane** | `scaffold-copy.ps1` / `.sh` | Operator workstation | Local FS + `git push` |
| **Runtime plane** | Generated repo's workflows + Terraform | GitHub Actions (OIDC) | Azure only |

The **only** manual step that cannot be automated is the initial human consent: an operator
must be signed in to `az`, `gh`, and hold a TFC token. Everything downstream is idempotent
and re-runnable.

The existing content is not discarded. `terraform/modules/*` (11 modules) and
`terraform/live/*` (5 layers) become the **template corpus** under `factory/templates/`,
parameterised with a token syntax the renderer resolves from the wizard's JSON.

---

## 2. Architecture Recommendation

### 2.1 Topology

```
factory (this repo)
├── site/                       # config plane — no network, no build step
├── factory/
│   ├── templates/              # tokenised source of every generated file
│   │   ├── terraform/          # ← promoted from today's terraform/
│   │   ├── .github/workflows/  # ← promoted from today's .github/workflows/
│   │   └── docs/
│   ├── schema/                 # JSON Schema for the config contract
│   ├── renderer/               # token resolution + conditional inclusion
│   └── discovery/              # read-only probes (Phase 0)
├── bootstrap-broker.ps1|.sh    # broker plane
├── scaffold-copy.ps1|.sh       # scaffold plane
├── factory-version.json        # version contract
└── generated-output/           # gitignored; per-company emission target
    └── <company-name>/
```

### 2.2 The config contract is the spine

Everything — wizard, renderer, broker, scaffold, generated Terraform, generated docs —
reads one artifact: `generated-output/<company>/lz-config.json`, validated against
`factory/schema/lz-config.schema.json`. This is non-negotiable: it is the single point
where drift between the UI and the Terraform variables can be detected mechanically.
A CI check in the factory diffs the schema against `variables.tf` in every template stack.

> This directly fixes the existing known defect where the generator's 47 policy toggles
> are not reconciled against `terraform/modules/policy-baseline/` (TODO.md).

### 2.3 Why a separate generated repo (vs. in-place)

- **Blast radius**: a factory bug cannot destroy a live customer landing zone.
- **Lifecycle**: the customer repo is versioned against `factory-version.json`, so
  upgrades are a diff-and-PR operation, not a re-clone.
- **Multi-tenancy**: one factory clone → N customer repos → N tenants, with no shared state.

### 2.4 Backend strategy

Support both, selected in the wizard, because the repo currently has a real split-brain:
`azurerm` native storage everywhere except the bootloader and workflow `010`, which assume
Terraform Cloud (TODO.md, Issue #11). The factory resolves this by making backend a
**first-class config choice** that drives which `backend.tf` template is rendered and which
broker steps execute. Default: **HCP Terraform** (state locking, audit, no chicken-and-egg
storage-account bootstrap). `azurerm` remains fully supported for air-gapped/sovereign.

---

## 3. Assumptions

| # | Assumption | If wrong |
|---|---|---|
| A1 | Operator has an interactive session for `az login` / `gh auth login`. | Broker cannot run headless; add device-code + PAT fallback path. |
| A2 | Entra role is Application Administrator *or* Global Administrator; Azure role is Owner or UAA **at the scope being managed** (tenant root for greenfield MG creation). | Readiness report emits FAIL; broker stops before mutating. |
| A3 | Generated repos are **private** by default. | Never relax without explicit config flag; OIDC subject claims leak repo topology. |
| A4 | One factory version produces one landing-zone version; mixed-version repos are not supported. | Upgrade guide handles N-1 only. |
| A5 | Brownfield discovery is **read-only** and never emits `terraform destroy`. | Hard requirement, enforced by workflow policy gate. |
| A6 | No customer data leaves the workstation from `site/`. Enforced by CSP + zero `fetch`/XHR. | Any network call in `site/` is a build-breaking CI failure. |
| A7 | Tenant root MG (`/providers/Microsoft.Management/managementGroups/<tenantId>`) is writable for greenfield. | Fall back to a designated intermediate root MG; config option `management_group_root_id`. |

---

## 4. Open Decisions

| # | Decision | Recommendation |
|---|---|---|
| D1 | Does the factory live in this repo, or is this repo retired as a customer instance? | **Build the factory here**; move existing `terraform/` + `.github/workflows/` under `factory/templates/`, and keep a `generated-output/hcw/` as the dogfood instance. |
| D2 | Default state backend. | HCP Terraform. |
| D3 | Do we emit one repo per company, or one repo per company-per-environment? | One repo per company; environments are TF workspaces + GitHub environments. |
| D4 | Broker identity model: one SP per repo, or one SP per environment? | **One app registration per environment per repo**, each with narrowly-scoped federated credentials. Blast radius over convenience. |
| D5 | Is Sentinel/Defender in the baseline or opt-in? | Opt-in via wizard; both modules are scaffold-only today and must be implemented before they can be offered. |
| D6 | Self-hosted runners supported? | Discovery detects them; v1 emits GitHub-hosted only, with a documented extension point. |

---

## 5. Risk Register

Severity: **H**igh / **M**edium / **L**ow. Every High risk has a named control.

### Architectural

| ID | Risk | Sev | Control |
|---|---|---|---|
| AR1 | Template drift: wizard emits variables the Terraform no longer accepts. | H | Schema↔`variables.tf` diff check in factory CI; renderer fails closed on unknown keys. |
| AR2 | Generated repo diverges from factory; upgrades become manual merges. | H | `factory-version.json` stamped into every generated repo + `upgrade-check` workflow that opens a PR on factory release. |
| AR3 | Monolithic state — one layer holds MGs, policy, and networking. | M | Existing 5-layer split is preserved and enforced; renderer refuses to merge layers. |
| AR4 | Token syntax collides with Terraform interpolation (`${}`). | M | Use `{{FACTORY:key}}` delimiters, never `${}`. |

### Operational

| ID | Risk | Sev | Control |
|---|---|---|---|
| OR1 | Broker partially fails, leaving orphaned Entra apps + half-configured repo. | H | Resumable state file (pattern already exists: `.lz-bootloader-state.json`) + `--rollback` emitting exact reversal commands. Idempotent by design. |
| OR2 | No verified green pipeline exists today (TODO.md: zero successful runs). | H | The factory cannot ship on an unproven pipeline. Gate: dogfood instance must show green `plan` + `apply` before v1.0.0. |
| OR3 | Operator runs scaffold over an existing generated dir, losing local edits. | M | `--dry-run` default posture; refuse non-empty target without `--force`; emit file inventory + diff. |
| OR4 | Day-2 owner unclear — factory team vs. customer platform team. | M | `docs/operating-model.md` assigns every generated artifact an owner persona. |

### Security

| ID | Risk | Sev | Control |
|---|---|---|---|
| SR1 | OIDC subject claim too broad (`repo:org/*:*`) grants any branch/PR the ability to apply. | H | Subject pinned to `repo:<owner>/<repo>:environment:<env>`; separate credential for `pull_request` (plan-only, Reader). This is the exact gap already found and fixed once in this repo — it must be structurally impossible to regress. |
| SR2 | Plan-time credential has write access. | H | Two identities per environment: `*-plan` (Reader + Storage Blob Data Reader) and `*-apply` (Contributor/Owner, environment-gated). |
| SR3 | Static client secrets fall back in when OIDC federation fails. | H | Broker has **no** secret-creation code path. Failure is fatal, not degraded. |
| SR4 | Unpinned third-party actions in generated workflows. | H | All actions SHA-pinned; `action-pinning-policy.yml` is emitted into every generated repo and required. |
| SR5 | Terraform state poisoning (state contains secrets / is writable by plan identity). | H | State isolated per layer per env; plan identity read-only on state; TFC state versioning + `state-recovery` runbook. |
| SR6 | Compromised runner exfiltrates tokens. | M | `permissions: {}` default at workflow root, least-privilege per job; no `pull_request_target`. |
| SR7 | Wizard writes secrets into `lz-config.json` which is then committed. | H | Schema forbids secret-typed fields; `.gitignore` covers `generated-output/`; secret-scan workflow in factory and generated repo. |
| SR8 | Repo compromise → attacker edits workflow to self-approve. | M | Branch protection + required reviewers on `prod` environment + CODEOWNERS on `.github/**`. |

### Scaling

| ID | Risk | Sev | Control |
|---|---|---|---|
| SC1 | Entra app registration quota / naming collisions across many tenants. | M | Deterministic naming `sp-{company}-{env}-{plan\|apply}`; discovery detects collisions pre-create. |
| SC2 | Management group operations are heavily throttled. | M | Serialise MG layer (`max-parallel: 1`, already the pattern); exponential backoff. |
| SC3 | Factory CI cost grows linearly with template count. | L | Path-filtered workflows. |

### Brownfield

| ID | Risk | Sev | Control |
|---|---|---|---|
| BR1 | Import of an existing resource produces a destructive plan. | H | `terraform plan` output parsed; any `destroy`/`replace` fails the run unless label `approved-destroy` is present. |
| BR2 | Discovery lacks read permission and silently reports "no resources". | H | Distinguish *empty* from *forbidden*; forbidden is a FAIL in the readiness report, never an empty inventory. |
| BR3 | Adopting a resource pulls unmanaged drift into scope. | M | Classification gate: Adopt / Ignore / Replace / Require-Approval, defaulting to Ignore. |

### OIDC

| ID | Risk | Sev | Control |
|---|---|---|---|
| OI1 | Federated credential missing for the `pull_request` trigger → all PR plans fail. | H | Broker creates the full credential matrix (branch, PR, environment, tag) and *verifies* by calling the token endpoint. This is the documented historical failure. |
| OI2 | Issuer/audience mismatch after GitHub or TFC changes. | M | `azure-auth-test.yml` emitted into every generated repo, scheduled weekly. |
| OI3 | Federated credential limit (20 per app) exhausted. | M | Per-environment apps keep the count low; discovery reports current count. |

### Governance

| ID | Risk | Sev | Control |
|---|---|---|---|
| GR1 | Policy baseline weakened silently by a generated-repo PR. | H | `terraform-policy-checks.yml` + Conftest deny rules on effect downgrades (`Deny`→`Audit`). |
| GR2 | Policy claims coverage it doesn't have. | M | Existing real example: the TLS module claims APIM coverage but lacks it (TODO.md). Add a doc↔code assertion test. |

### GitHub

| ID | Risk | Sev | Control |
|---|---|---|---|
| GH1 | Personal accounts cannot use environments/branch protection on private repos. | H | Discovery detects plan tier; broker degrades gracefully and **reports the reduced control set explicitly** rather than silently skipping. |
| GH2 | Org policy blocks Actions or requires allow-listed actions. | M | Discovery reads org Actions policy; readiness WARN with remediation. |
| GH3 | Repo name collision. | L | Pre-flight check; `--repo-name` override. |

### Terraform

| ID | Risk | Sev | Control |
|---|---|---|---|
| TR1 | Provider major-version bump breaks generated repos. | H | Lock files committed; `factory-version.json` pins provider ranges; Dependabot PRs gated by plan. |
| TR2 | TFC workspace created without correct execution mode / working dir. | M | Broker sets and verifies; audit report records final state. |
| TR3 | State lock left held after a cancelled run. | M | `state-validation` workflow + documented force-unlock runbook with approval. |

---

## 6. Repository Structure (factory)

See §2.1. Full generated-repo structure is specified in `docs/factory/GENERATED-REPO.md`
(produced during build).

---

## 7. Identity Architecture

Six trust relationships, all OIDC where the platform supports it:

| # | Source | Target | Method | Credential | Rotation |
|---|---|---|---|---|---|
| 1 | GitHub Actions (env `<e>`) | Azure | Workload identity federation | None (OIDC) | N/A |
| 2 | GitHub Actions | HCP Terraform | OIDC dynamic credentials | None | N/A |
| 3 | HCP Terraform | Azure | TFC dynamic provider credentials | None | N/A |
| 4 | Bootstrap operator | Azure | `az login` (interactive, MFA) | User token | Session |
| 5 | Bootstrap operator | GitHub | `gh auth login` (device flow) | User token | Session |
| 6 | Bootstrap operator | HCP Terraform | User API token | Token (only static credential in the system) | 90 days, documented |

Relationship 6 is the sole static credential and exists only on the operator workstation,
never in CI. Full matrix with permissions, token lifetimes, ownership, and recovery
procedures → `docs/identity-trust-matrix.md`.

Per environment, two apps:

- `sp-{company}-{env}-plan` — Reader at scope + state read. Federated to
  `repo:{owner}/{repo}:pull_request`.
- `sp-{company}-{env}-apply` — least role sufficient for the layer. Federated to
  `repo:{owner}/{repo}:environment:{env}` only.

---

## 8. Governance Architecture

Five layers, each with an owner, RBAC model, policy set, and diagnostic target:
Tenant → Management Group → Subscription → Resource Group → Resource.
Implemented in Stage 8 under `factory/templates/docs/`. Policy-as-code in four dialects (Azure Policy,
OPA/Rego, Conftest, Sentinel) covering naming, tagging, security, regions, public
endpoints, networking, diagnostics, encryption, cost.

---

## 9. Deployment Architecture

Layer order is preserved from the existing repo and is a hard dependency chain:

`global` (MGs + policy) → `platform-identity` → `platform-connectivity` →
`platform-management` → `platform-shared-services` → `workloads-{env}` → `sandbox`

Each layer = one state file = one TFC workspace = one GitHub environment gate.

---

## 10. Workflow Architecture

Generated into every customer repo, all SHA-pinned, all `permissions: {}` by default:

`000-bootstrap-validation` · `010-terraform-init` · `020-rbac-validation` ·
`terraform-fmt-validate` · `terraform-plan` · `terraform-apply` · `security-scan` ·
`policy-checks` · `drift-detection` (scheduled) · `brownfield-discovery` (manual) ·
`destroy-protection` · `compliance-validation` · `environment-promotion` ·
`dependency-updates` · `upgrade-check`

---

## 11. Phase Model

| Phase | Name | Gate |
|---|---|---|
| 0 | Discovery | Inventory complete, no FORBIDDEN results |
| 1 | Readiness validation | Zero FAIL |
| 2 | Bootstrap | Broker exits 0, audit report clean |
| 3 | Identity | Federated credential token exchange **verified live** |
| 4 | GitHub | Repo + protection + environments confirmed via API read-back |
| 5 | Terraform backend | Workspace reachable, state lock acquired/released |
| 6 | Repository construction | Scaffold inventory matches manifest |
| 7 | LZ configuration | `terraform validate` green on all layers |
| 8 | Validation | Plan green, zero destroys |
| 9 | Deployment | Apply green per layer in order |
| 10 | Post-deploy validation | Policy compliance ≥ threshold, diagnostics flowing |
| 11 | Drift monitoring | Scheduled drift job green |
| 12 | Operations | Runbooks + on-call handoff signed off |

Each phase's inputs/outputs/dependencies/success/failure/rollback → `docs/phase-model.md`.

---

## 12. File Generation Order

Dependency-ordered; each stage is independently reviewable.

1. `factory/schema/lz-config.schema.json` — the contract, first, because everything reads it
2. `factory-version.json`
3. `site/` (index.html, app.js, styles.css) — emits config conforming to (1)
4. `factory/discovery/` — Phase 0 probes (read-only)
5. `factory/renderer/` — token resolution engine
6. `factory/templates/terraform/**` — promoted + tokenised from existing modules/layers
7. `factory/templates/.github/workflows/**` — promoted + tokenised
8. `factory/templates/docs/**` — self-documenting corpus
9. `bootstrap-broker.ps1` / `.sh`
10. `scaffold-copy.ps1` / `.sh`
11. `docs/**` — factory-level docs (identity matrix, operating model, governance, security, threat model, observability, finops, state management, upgrade guide, DR, phase model)
12. Factory CI — schema↔variables drift check, site-no-network check, shellcheck/PSScriptAnalyzer
13. Dogfood instance — regenerate `generated-output/hcw/` and prove green

---

## 13. Complete Repository Content

Built in the order above. Every template file carries a header comment naming the config
keys it consumes, so replacement of any placeholder is mechanically traceable — there are
no unexplained placeholders.
