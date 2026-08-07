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
validation evidence. Brownfield configurations
use the Stage 11 generator to create reviewable import artifacts without
executing Terraform import. Stage 12 provides the credential-free Factory CI
gate, and Stage 13 provides the protected HCW dogfood render/plan/apply path.
Stage 14 aggregates retained evidence and computes a review-only release
promotion proposal.

**How it works**:

1. `site/` exports the versioned `lz-config.json` contract.
2. `factory/discovery/` produces a read-only readiness report and
   `discovery-inventory.json`.
3. `factory/renderer/` emits Terraform, workflows, documentation, and
   `USER-CHECKLIST.md`.
4. `bootstrap-broker.ps1` / `.sh` plans by default and idempotently reconciles
   Entra, RBAC, GitHub, and backend prerequisites only in apply mode.
5. `brownfield-import.ps1` / `.sh` classifies discovered resources and, only
   for explicit Adopt decisions, registers import blocks/review commands before
   scaffolding.
6. `scaffold-copy.ps1` / `.sh` verifies the exact augmented renderer inventory,
   plans by default, and creates/commits/pushes the generated repository only in
   apply mode.
7. `.github/workflows/factory-ci.yml` runs every factory contract, policy,
   analyzer, and Terraform corpus check and uploads machine-readable evidence.
8. `.github/workflows/dogfood-instance.yml` regenerates the HCW instance from
   repository variables and runs an explicit render, read-only plan, or
   protected apply with retained evidence.
9. `.github/workflows/release-readiness.yml` hash-binds Factory CI, full
   dogfood apply, and independent read-back evidence to a five-gate promotion
   proposal without changing the release contract.

> **Status**: Stages 1–14 are implemented. Live Factory CI, dogfood
> plan/apply/read-back, evidence attestation, and any release-gate PR remain
> operator activities. All gates remain evidence-driven. See
> [TODO.md](TODO.md) and [docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md).

---

## Repository Structure

```
HCW-Demo-LZDeployment/
├── scripts/
│   ├── Initialize-ClientFork.ps1          # Plan-first private-copy creation (mirror push + visibility read-back; hardening retired, decision 0007)
│   ├── Invoke-CustomerEngagement.ps1      # Plan-first wrapper: discovery → broker → render → validate → scaffold
│   ├── New-BackendConfig.ps1              # Plan-first per-layer backend.hcl generator (AAD auth enforced)
│   ├── Add-PlanFederatedCredential.ps1    # Plan-first AADSTS700213 remediation for the plan SP
│   ├── Dispose-Engagement.ps1             # Plan-first engagement disposal (archive, then delete)
│   ├── Start-LandingZoneBootstrap.ps1    # Legacy single-repo bootstrap; retained for compatibility
│   └── utilities/                         # Standalone operator utilities — nothing calls these (see its README)
│       ├── Configure-DeploymentOptions.ps1  # Records optional-module choices (planning-only artifact)
│       ├── Validate-ALZDeployment.ps1
│       ├── Verify-CostAccuracy.ps1
│       └── Invoke-BulkOperations.ps1
├── terraform/
│   ├── backend-bootstrap/       # One-time state storage setup
│   ├── modules/                 # 11 reusable Terraform modules
│   │   ├── management-groups/   # Management group hierarchy
│   │   ├── hub-network/         # Dual-region hubs with firewall + threat intel
│   │   ├── spoke-network/       # Workload spokes with hub peering
│   │   ├── policy-baseline/     # Azure Policy governance (TLS 1.2, tagging, etc.)
│   │   ├── backup-baseline/     # Recovery Services + Backup Vaults
│   │   ├── nsg-flow-logs/       # NSG flow logs + Traffic Analytics
│   │   ├── defender-baseline/   # Microsoft Defender for Cloud (optional, not auto-deployed)
│   │   ├── sandbox/             # Isolated sandbox resource group (feature-toggled)
│   │   ├── keyvault-cmk/        # Customer-managed keys (scaffold only, not implemented)
│   │   ├── sentinel-siem/       # Azure Sentinel (scaffold only, not implemented)
│   │   └── management-baseline/
│   ├── live/                    # Environment-specific deployments
│   │   ├── global/                  # Management groups + policies
│   │   ├── platform-connectivity/   # Hubs and firewalls
│   │   ├── platform-management/     # Backup + automation
│   │   ├── workloads-prod/          # Production spokes
│   │   └── sandbox/                 # Isolated sandbox environment
│   └── scripts/
│       └── Cleanup-ExpiredSandboxResources.ps1
├── frontend/                     # Static, backend-free .tfvars generator (see the wiki's Webapp-Plan page)
│   ├── index.html
│   ├── app.js
│   └── styles.css
├── .github/workflows/
│   ├── 010-terraform-init.yml       # Terraform init + workload setup
│   ├── 020-rbac-validation.yml      # Service principal RBAC audit
│   ├── terraform-plan.yml           # PR-based plan and validation
│   ├── terraform-apply.yml          # Dispatch-only, saved-plan deployment (merging never deploys)
│   ├── secrets-scan.yml             # TruffleHog + Gitleaks + tfsec + committed-state check
│   ├── deploy-pages.yml             # GitHub Pages deploy: site/ at root, frontend/ under /frontend/ (Pages source must be "GitHub Actions")
│   └── action-pinning-policy.yml    # Enforces SHA-pinned actions
├── bootstrap-broker.ps1          # Stage 9 non-interactive broker
├── bootstrap-broker.sh           # Cross-platform launcher
├── validate-render.ps1           # Post-render validation gate (fmt, init, validate, pinning, lint, scan)
├── validate-render.sh            # Cross-platform launcher
├── scaffold-copy.ps1             # Stage 10 plan-first scaffold builder
├── scaffold-copy.sh              # Cross-platform launcher
├── brownfield-import.ps1         # Stage 11 brownfield import generator
├── brownfield-import.sh          # Cross-platform launcher
├── factory/validate/             # Post-render validation gate module
├── factory/ci/                   # Stage 12 CI runner and source policies
├── factory/dogfood/              # Stage 13 dogfood orchestration and evidence
├── factory/release/              # Stage 14 attestation and promotion planning
├── dogfood-instance.ps1          # Stage 13 PowerShell entry point
├── dogfood-instance.sh           # Stage 13 strict Bash launcher
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

### Brownfield adoption

```powershell
# Generate the classification template and plan
$env:LZ_BROWNFIELD_CLASSIFICATIONS = './brownfield-classifications.json'
$env:LZ_IMPORT_EVIDENCE = './brownfield-evidence'
pwsh ./brownfield-import.ps1

# Write approved review artifacts into the rendered tree
$env:LZ_IMPORT_APPLY = 'true'
pwsh ./brownfield-import.ps1
```

Only explicit Adopt entries with exact Terraform addresses and active layers
produce artifacts. Ignore emits nothing; Replace and Require-Approval remain
operator gates. The generator never executes Terraform import.

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

Once the generated repository is published, the numbered workflows take over:

- `010-terraform-init.yml` initializes Terraform and validates the workload setup
- `020-rbac-validation.yml` audits service principal RBAC (also runs weekly)
- PRs touching `terraform/**` trigger `terraform-plan.yml`; after merge, an operator dispatches `terraform-apply.yml` per layer (**merging alone deploys nothing** — dispatch-only since 2026-08-02)

Each layer under `terraform/live/` deploys independently and in dependency order: `global` → `platform-connectivity` → `platform-management` → `workloads-prod` → `sandbox`.

---

## Optional Static Configuration Generator

`frontend/` is a standalone static page for the **legacy in-repo pipeline** — open `frontend/index.html` in a browser, no server required (`site/` is the primary path for customer engagements). It lets you pick org name, region, network topology, and options, then emits two layer-accurate variable files: `terraform.auto.tfvars` (for `terraform/live/global`) and `connectivity.auto.tfvars` (for `terraform/live/platform-connectivity`). Policy toggles are presented honestly: the baseline's enforced policies are listed separately from catalog entries marked "not yet enforced". Usage and placement: [frontend/README.md](frontend/README.md); background: [Webapp-Plan on the wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki/Webapp-Plan).

---

## Key Features

### Firewall Choice
Select at deployment time via the `firewall_type` variable in the `platform-connectivity` layer: Azure Firewall (`azfw`), Palo Alto (`palo`), or Fortinet (`fortinet`).

### Sandbox with Auto-Expiry
- Sandbox resources require an `expiry_date` tag (`YYYY-MM-DD`)
- `Cleanup-ExpiredSandboxResources.ps1` validates the subscription is GUID-formatted and tagged `purpose=sandbox` before touching anything, supports `-DryRun` (default on), and enforces a max-deletion limit
- The sandbox module (`terraform/modules/sandbox/`) is feature-toggled off by default (`create_sandbox_rg = false`)

### Governance via Azure Policy
Policy baseline module enforces mandatory tagging, allowed locations, NSG requirements, TLS 1.2 minimum (Storage, App Service, Function Apps, MySQL, PostgreSQL, and — since 2026-08-02 — API Management), and sandbox isolation rules.

### GitOps Workflow
- PR opened against `main` touching `terraform/**` → `terraform plan` runs, posts results to the PR
- After merge, an operator dispatches `terraform-apply.yml` per layer (Actions → Terraform Apply → pick layer): trusted-`main` checkout, hard layer allowlist, saved plan (`plan -out=tfplan`), destructive-plan refusal, then apply of exactly that plan — **merging to `main` never deploys** (dispatch-only since 2026-08-02)
- Production layers use a GitHub environment gate; sandbox uses its own environment

---

## Current Known Issues

See [TODO.md](TODO.md) (all action items, phased) and [REVIEW.md](REVIEW.md) (human-resolvable blockers) for the full, current lists. Highlights:

- CI/CD pipeline has no recorded successful run yet — read-only live discovery (2026-08-01) found that no landing-zone identity estate exists: no app registrations, no `AZURE_PLAN_CLIENT_ID` or `TF_API_TOKEN` secret, and no dev/prod/hub environments. The remediation is running the Phase-2 bootstrap end-to-end in the confirmed engagement tenant, not credential patching; see [REVIEW.md](REVIEW.md) §1 / [TODO.md](TODO.md) item 4.1
- Backend is currently `azurerm` native storage everywhere except the bootloader and workflow `010`, which assume Terraform Cloud — migration tracked as [GitHub Issue #11](https://github.com/HybridCloudWorks/Template-LZDeployment/issues/11)
- Two modules (`keyvault-cmk`, `sentinel-siem`) are scaffold-only stubs with no real resources yet
- 4 utility scripts (`Configure-DeploymentOptions.ps1`, `Invoke-BulkOperations.ps1`, `Validate-ALZDeployment.ps1`, `Verify-CostAccuracy.ps1`) aren't called from anywhere in the pipeline — they now live in [`scripts/utilities/`](scripts/utilities/README.md), clearly separated from the core flow; wiring `Configure-DeploymentOptions.ps1` in is tracked in [REVIEW.md](REVIEW.md) §16 / [TODO.md](TODO.md) item 2.5

---

## Technology Stack

| Component | Technology | Version |
|---|---|---|
| IaC | Terraform | 1.9+ |
| Cloud Provider | Azure | azurerm provider ~> 5.0 (operator-ratified 2026-08-06; enforced by `factory/ci/Test-ProviderConstraints.ps1`) |
| CI/CD | GitHub Actions | OIDC-authenticated |
| State Backend | Azure Storage (native), migrating to Terraform Cloud | — |
| Governance | Azure Policy | Built-in + custom policy definitions |
| Config Generator | Static HTML/CSS/vanilla JS | No backend, no build step |

---

## Documentation

- **[GitHub wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki)** — build docs, factory design and Stage 7–14 readiness records, and the webapp/static-generator docs (migrated from `docs/` on 2026-08-01)
- **[TODO.md](TODO.md)** — all action items repo-wide, phased for handoff
- **[REVIEW.md](REVIEW.md)** — blockers only a human-in-the-loop can resolve
- **[CHANGELOG.md](CHANGELOG.md)** — changelog of shipped features, with verification notes and the archived `HANDOFF.md` decisions
- **[docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)** — operator authentication, publication, and verification activities
- **[docs/runbooks/](docs/runbooks/)** — engagement disposal, lifecycle-hygiene, and Stage 13 execution runbooks; **[docs/decisions/](docs/decisions/)** — decision records
- **[docs/CROSS-DOMAIN-CONTRACTS.md](docs/CROSS-DOMAIN-CONTRACTS.md)** — load-bearing cross-file contracts (stays in-repo; agents read it from disk)
- **[terraform/modules/\*/README.md](terraform/modules/)** — per-module usage docs (all 11 modules, as of 2026-08-02)

---

## Naming Convention

Follows [Microsoft CAF naming standards](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming):

- Management Groups: `mg-{scope}`
- Resource Groups: `rg-{scope}-{region}-{env}-{nn}`
- Resources: `{type}-{name}-{region}-{env}-{nn}`

## Tagging Strategy

Mandatory tags enforced via policy baseline: `owner`, `application`, `environment` (`prod`/`nonprod`/`sandbox`), `cost_center`. Sandbox resources additionally require `expiry_date`.
