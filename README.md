# HCW Azure Landing Zone Deployment

## Overview

This repository is the Landing Zone Factory. It renders a self-contained landing
zone repository from `lz-config.json`, discovers existing tenant state, and uses
the Stage 9 broker to reconcile external prerequisites before the Stage 10
scaffold builder publishes the generated repository. Between render and
scaffold, the post-render validation gate (`validate-render.ps1` / `.sh`)
proves the rendered tree is deployable — terraform validate, formatting,
workflow SHA pinning, provider-constraint integrity, lint, and security
scanning — and scaffold apply refuses a render without passing, current
validation evidence. The repository is a **generator only**
([ADR 0013](docs/decisions/0013-generator-only-avm-architecture.md)): it
carries no working Terraform tree, and the rendered output contains no
vendored modules — three root-module layers (`platform-management`,
`global`, `platform-connectivity`) reference Azure Verified Modules by
pinned registry source and version. Stage 12 provides the credential-free
Factory CI gate; the former Stage 13 dogfood path was replaced by the
end-to-end generation proof (`factory-version.json` `releaseGates`).
Stage 14 aggregates retained evidence and computes a review-only release
promotion proposal.

**How it works**:

1. `site/` exports the versioned `lz-config.json` contract. **One command to
   start the wizard** (no server, no build, no network):

   ```bash
   xdg-open site/index.html   # macOS: open site/index.html — or use the GitHub Pages deployment
   ```
2. `factory/discovery/` produces a read-only readiness report and
   `discovery-inventory.json`.
3. `factory/renderer/` emits the three AVM-referencing Terraform layers,
   workflows, documentation, and `USER-CHECKLIST.md`.
4. `bootstrap-broker.ps1` / `.sh` plans by default and idempotently reconciles
   Entra, RBAC, GitHub, and backend prerequisites only in apply mode.
5. `scripts/New-LzSubscriptions.ps1` creates the subscriptions the wizard
   planned by name (create mode) and writes the IDs back into
   `lz-config.json` ([ADR 0020](docs/decisions/0020-subscription-vending.md)).
6. `scaffold-copy.ps1` / `.sh` verifies the exact augmented renderer inventory,
   plans by default, and creates/commits/pushes the generated repository only in
   apply mode (App/PAT/interactive delivery auth —
   [ADR 0014](docs/decisions/0014-delivery-auth-app-pat-and-template-instantiation.md)).
7. `.github/workflows/factory-ci.yml` runs every factory contract, policy,
   analyzer, and template-corpus check and uploads machine-readable evidence;
   `.github/workflows/terraform-policy-checks.yml` renders both topology
   fixtures and runs `terraform init`/`validate` on the rendered output — the
   execution-time verification of the AVM pins.
8. `.github/workflows/release-readiness.yml` hash-binds Factory CI,
   end-to-end generation evidence, and independent read-back evidence to a
   promotion proposal without changing the release contract.

> **Status**: the generator-only model (factory 0.11.0, ADRs 0013–0020) is
> implemented, including subscription vending, exclude-and-create
> brownfield, and the hardened state posture. Live Factory CI, the
> end-to-end generation proof, evidence attestation, and any release-gate PR
> remain operator activities. All gates remain evidence-driven. See
> [TODO.md](TODO.md) and [docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md).

---

## Repository Structure

```
HCW-Demo-LZDeployment/
├── scripts/
│   ├── Initialize-ClientFork.ps1          # Plan-first private-copy creation (mirror push + visibility read-back; hardening retired, decision 0007)
│   ├── Invoke-CustomerEngagement.ps1      # Plan-first wrapper: discovery → broker → render → validate → scaffold
│   ├── Add-PlanFederatedCredential.ps1    # Plan-first AADSTS700213 remediation for the plan SP
│   ├── Dispose-Engagement.ps1             # Plan-first engagement disposal (archive, then delete)
│   ├── Start-LandingZoneBootstrap.ps1    # Legacy single-repo bootstrap; retained for compatibility
│   └── utilities/                         # Standalone operator utilities — nothing calls these (see its README)
│       ├── Configure-DeploymentOptions.ps1  # Records optional-module choices (planning-only artifact)
│       ├── Validate-ALZDeployment.ps1
│       ├── Verify-CostAccuracy.ps1
│       └── Invoke-BulkOperations.ps1
├── factory/templates/            # The emitted-output corpus (ADR 0013)
│   ├── terraform/live/           # Three AVM-referencing root-module layers
│   │   ├── platform-management/     # Azure/avm-ptn-alz-management 0.9.0
│   │   ├── global/                  # Azure/avm-ptn-alz 0.21.0 (ALZ library platform/alz @ 2026.04.2)
│   │   ├── platform-connectivity/   # hub-and-spoke 0.17.3 OR virtual-wan 0.17.1, by topology answer
│   │   └── _layer/                  # Per-layer backend.tf (empty azurerm block) + backend.hcl (OIDC + AAD)
│   ├── .github/workflows/        # Emitted, self-contained, SHA-pinned workflows (ADR 0016)
│   ├── docs/                     # Emitted governance/finops/operating-model docs
│   └── renovate.json             # Pin ownership transfers to the generated repo (ADR 0013)
├── frontend/                     # DEPRECATED legacy .tfvars generator (banner in page; site/ is the product)
│   ├── index.html
│   ├── app.js
│   └── styles.css
├── .github/workflows/
│   ├── factory-ci.yml               # Canonical generator CI (contracts, policies, analyzers)
│   ├── terraform-policy-checks.yml  # Renders both topology fixtures; init/validate on rendered output (AVM pin verification)
│   ├── release-readiness.yml        # Binds e2e generation evidence to the promotion proposal
│   ├── secrets-scan.yml             # TruffleHog + Gitleaks + tfsec + committed-state check
│   ├── deploy-pages.yml             # GitHub Pages deploy: site/ at root, frontend/ under /frontend/ (Pages source must be "GitHub Actions")
│   └── action-pinning-policy.yml    # Enforces SHA-pinned actions
├── bootstrap-broker.ps1          # Stage 9 non-interactive broker
├── bootstrap-broker.sh           # Cross-platform launcher
├── validate-render.ps1           # Post-render validation gate (fmt, init, validate, pinning, lint, scan)
├── validate-render.sh            # Cross-platform launcher
├── scaffold-copy.ps1             # Stage 10 plan-first scaffold builder
├── scaffold-copy.sh              # Cross-platform launcher
├── scripts/New-LzSubscriptions.ps1  # Subscription vending: creates planned subscriptions, patches IDs back (ADR 0020)
├── factory/validate/             # Post-render validation gate module
├── factory/ci/                   # Stage 12 CI runner and source policies
├── factory/release/              # Stage 14 attestation and promotion planning
├── release-readiness.ps1         # Stage 14 PowerShell entry point
├── release-readiness.sh          # Stage 14 strict Bash launcher
├── docs/
│   ├── USER-CHECKLIST.md         # Operator authentication, publication, and verification
│   ├── decisions/                # Decision records
│   ├── runbooks/                 # Operator procedures
│   └── wiki-review/              # 2026-08-06 wiki source-material review evidence
├── TODO.md                       # All action items, phased for handoff
├── REVIEW.md                     # Blockers only a human-in-the-loop can resolve
├── CHANGELOG.md                  # Changelog of shipped features
└── README.md                     # This file
```

---

## Getting Started

### Prerequisites
- Azure CLI 2.69+
- Terraform 1.9+
- GitHub CLI 2.67+
- Git 2.43+
- Owner/User Access Administrator at the Azure tenant root (for OIDC/RBAC setup)
- An Azure subscription

### Bootstrap

```powershell
# Plan only
pwsh ./bootstrap-broker.ps1 -ConfigPath ./lz-config.json `
  -DiscoveryPath ./discovery-inventory.json

# Apply after reviewing bootstrap-plan.json
$env:LZ_BOOTSTRAP_APPLY = 'true'
pwsh ./bootstrap-broker.ps1
```

The broker is non-interactive and idempotent. Tenant-specific inputs come from
the config/discovery contracts and environment variables documented in
[docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md).

### Scaffold

```powershell
# Plan only
$env:LZ_RENDERED_PATH = './generated-output/contoso/repo'
$env:LZ_SCAFFOLD_TARGET = './customer-repos/contoso'
pwsh ./scaffold-copy.ps1

# Apply after reviewing scaffold-plan.json
$env:LZ_SCAFFOLD_APPLY = 'true'
pwsh ./scaffold-copy.ps1
```

The builder fails closed on missing, extra, duplicate, absolute, or traversal
manifest paths. A non-empty target requires explicit force and is retained as a
timestamped sibling backup.

### Brownfield — exclude and create

Brownfield means **new subscriptions alongside the existing estate**, never
adoption ([ADR 0018](docs/decisions/0018-brownfield-exclude-and-create.md)):
excluded subscriptions
(`deploymentStrategy.brownfield.excludedSubscriptionIds`) stay outside the
new management-group hierarchy and are never planned, imported, or modified.
Discovery inventories existing tenant-scope policy assignments read-only so
baseline collisions are visible before the first apply. The former
`brownfield-import` import-block generator (quarantined since the bespoke
corpus was retired, CLASSIFICATION UNRESOLVED-2) was removed with ADR 0018 —
integration of existing deployments is out of scope for the factory.

### Factory CI

Factory CI runs automatically for relevant pull requests and protected-branch
pushes. It can also run on a provisioned workstation:

```powershell
$env:LZ_FACTORY_CI_OUTPUT = './factory-ci-output'
pwsh ./factory/ci/Invoke-FactoryCI.ps1
```

The stable GitHub context is `Factory CI` (GitHub records the job-level check
name). The runner uses no
cloud credentials, initializes Terraform with backends disabled, and writes
`factory-ci-report.json` plus per-check logs.

### After Scaffold

Once the generated repository is published, its **emitted, self-contained
workflows** ([ADR 0016](docs/decisions/0016-self-contained-emitted-workflows.md))
take over: plan on PR, dispatch-only apply, auth test, fmt/validate,
policy-diff guardrails, security scan, and the action-pinning policy — all
SHA-pinned, with no dependency back on this factory.

The generated repository's three layers deploy independently and in
dependency order: `platform-management` → `global` → `platform-connectivity`
(the `global` layer reads platform-management's state for the Log Analytics
policy default). `terraform init` in the generated repository downloads the
pinned AVM modules from the Terraform Registry; from delivery onward the
emitted `renovate.json` owns those pins.

---

## Optional Static Configuration Generator (deprecated)

`frontend/` is a standalone static page that fed the **retired legacy
in-repo pipeline** (the `terraform/live/*` tree deleted by
[ADR 0013](docs/decisions/0013-generator-only-avm-architecture.md)). It is
retained with an explicit deprecation banner pointing at `site/`, the only
supported path; its role is now historical/documentation-only. Usage and
background: [frontend/README.md](frontend/README.md) and
[Webapp-Plan on the wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki/Webapp-Plan).

---

## Key Features

### Firewall
Azure Firewall only, tier selected in the wizard
(`connectivity.firewall.azfwTier`). The `palo`/`fortinet` NVA options were
retired with the bespoke corpus — third-party NVA insertion is per-estate
work in the generated repository
([ADR 0017](docs/decisions/0017-wizard-scope-vs-emitted-architecture.md)).

### Topology Choice
Hub-and-spoke **or** Virtual WAN, selected by the wizard's
`connectivity.model` answer — the rendered `platform-connectivity` layer
contains exactly one AVM connectivity pattern module, never both
([ADR 0013](docs/decisions/0013-generator-only-avm-architecture.md)).
Workload spokes and sandbox estates are per-estate work in the generated
repository (ADR 0017).

### Governance via the ALZ Library
Policy definitions, assignments, and the management-group archetypes come
from the pinned ALZ library (`platform/alz` @ `2026.04.2`) through the
`avm-ptn-alz` pattern module and the `alz` provider — the bespoke policy
baseline module is retired (ADR 0013).

### GitOps Workflow (emitted into the generated repository)
- PR opened against `main` touching `terraform/**` → the emitted plan
  workflow runs and posts results to the PR
- After merge, an operator dispatches the emitted apply workflow per layer —
  **merging alone deploys nothing** (dispatch-only)
- Platform layers use GitHub environment gates provisioned by the broker;
  all workflows are self-contained and SHA-pinned
  ([ADR 0016](docs/decisions/0016-self-contained-emitted-workflows.md))

---

## Current Known Issues

See [TODO.md](TODO.md) (all action items, phased) and [REVIEW.md](REVIEW.md) (human-resolvable blockers) for the full, current lists. Highlights:

- CI/CD pipeline has no recorded successful run yet — read-only live discovery (2026-08-01) found that no landing-zone identity estate exists: no app registrations, no `AZURE_PLAN_CLIENT_ID` or `TF_API_TOKEN` secret, and no dev/prod/hub environments. The remediation is running the Phase-2 bootstrap end-to-end in the confirmed engagement tenant, not credential patching; see [REVIEW.md](REVIEW.md) §1 / [TODO.md](TODO.md) item 4.1
- Backend is `azurerm` native storage **everywhere** — the only backend in the schema, wizard, and templates, OIDC + Azure AD auth only ([ADR 0015](docs/decisions/0015-azurerm-only-emitted-backend.md); Issue #11 closed "standardize, don't migrate" by decision 0011, and the dual-backend render feature was retired by ADR 0015)
- Key Vault CMK and Sentinel answers are **recorded-not-deployed** ([ADR 0017](docs/decisions/0017-wizard-scope-vs-emitted-architecture.md)) — the former `keyvault-cmk`/`sentinel-siem` scaffold modules were deleted with the bespoke corpus; the wizard warns and the answers survive in the committed answer record
- Brownfield is **exclude-and-create** ([ADR 0018](docs/decisions/0018-brownfield-exclude-and-create.md)) — the quarantined `brownfield-import` generator was removed; integrating existing deployments is out of scope
- 4 utility scripts (`Configure-DeploymentOptions.ps1`, `Invoke-BulkOperations.ps1`, `Validate-ALZDeployment.ps1`, `Verify-CostAccuracy.ps1`) aren't called from anywhere in the pipeline — they now live in [`scripts/utilities/`](scripts/utilities/README.md), clearly separated from the core flow; wiring `Configure-DeploymentOptions.ps1` in is tracked in [REVIEW.md](REVIEW.md) §16 / [TODO.md](TODO.md) item 2.5

---

## Technology Stack

| Component | Technology | Version |
|---|---|---|
| IaC | Terraform | 1.9+ |
| Cloud Provider | Azure | azurerm `~> 4.0`, `Azure/alz` `~> 0.21.0`, `Azure/azapi` `~> 2.12` (canonical constraints in `factory/ci/Test-ProviderConstraints.ps1`) |
| Modules | Azure Verified Modules | Pinned registry references, never vendored ([ADR 0013](docs/decisions/0013-generator-only-avm-architecture.md)); Renovate owns pins in the generated repo |
| CI/CD | GitHub Actions | OIDC-authenticated |
| State Backend | Azure Storage (native azurerm), OIDC + Azure AD only | [ADR 0015](docs/decisions/0015-azurerm-only-emitted-backend.md) |
| Governance | Azure Policy via the ALZ library | `platform/alz` @ `2026.04.2` |
| Config Generator | Static HTML/CSS/vanilla JS | No backend, no build step |

---

## Documentation

- **[GitHub wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki)** — build docs, factory design and Stage 7–14 readiness records, and the webapp/static-generator docs (migrated from `docs/` on 2026-08-01)
- **[TODO.md](TODO.md)** — all action items repo-wide, phased for handoff
- **[REVIEW.md](REVIEW.md)** — blockers only a human-in-the-loop can resolve
- **[CHANGELOG.md](CHANGELOG.md)** — changelog of shipped features, with verification notes and the archived `HANDOFF.md` decisions
- **[docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)** — operator authentication, publication, and verification activities
- **[docs/runbooks/](docs/runbooks/)** — engagement disposal, lifecycle-hygiene, and go-live runbooks (the Stage 13 dogfood runbook is historical — ADR 0013); **[docs/decisions/](docs/decisions/)** — decision records
- **[docs/CROSS-DOMAIN-CONTRACTS.md](docs/CROSS-DOMAIN-CONTRACTS.md)** — load-bearing cross-file contracts (stays in-repo; agents read it from disk)
- **[docs/refactor/](docs/refactor/)** — the 2026-08-15 generator-only refactor gate documents (classification, coverage, output contract, placeholders)

---

## Naming Convention

The wizard collects and validates naming patterns against
[Microsoft CAF naming standards](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming),
and the answers flow into the generated documentation. Resource names
**inside** the AVM pattern modules follow the modules' own conventions
([ADR 0017](docs/decisions/0017-wizard-scope-vs-emitted-architecture.md)).

## Tagging Strategy

Default tags come from the wizard (`naming.defaultTags`, guard G06 enforces
policy-required coverage) and flow into every emitted layer; tag enforcement
policy comes from the pinned ALZ library rather than a bespoke policy module
(ADR 0013).
