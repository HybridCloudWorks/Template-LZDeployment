# HCW Azure Landing Zone Deployment

## Overview

This repository is the Landing Zone Factory. It renders a self-contained landing
zone repository from `lz-config.json`, discovers existing tenant state, and uses
the Stage 9 broker to reconcile external prerequisites before the Stage 10
scaffold builder publishes the generated repository. Brownfield configurations
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
> [TODO.md](TODO.md) and [USER-CHECKLIST.md](USER-CHECKLIST.md).

---

## Repository Structure

```
HCW-Demo-LZDeployment/
├── scripts/
│   ├── Start-LandingZoneBootstrap.ps1    # Legacy single-repo bootstrap; retained for compatibility
│   ├── Configure-DeploymentOptions.ps1    # Interactively enable optional modules
│   ├── Validate-ALZDeployment.ps1
│   ├── Verify-CostAccuracy.ps1
│   └── Invoke-BulkOperations.ps1
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
├── frontend/                     # Static, backend-free .tfvars generator (see docs/webapp/PLAN.md)
│   ├── index.html
│   ├── app.js
│   └── styles.css
├── .github/workflows/
│   ├── 010-terraform-init.yml       # Terraform init + workload setup
│   ├── 020-rbac-validation.yml      # Service principal RBAC audit
│   ├── terraform-plan.yml           # PR-based plan and validation
│   ├── terraform-apply.yml          # Merge-based deployment
│   ├── secrets-scan.yml             # TruffleHog + Gitleaks + tfsec
│   └── action-pinning-policy.yml    # Enforces SHA-pinned actions
├── bootstrap-broker.ps1          # Stage 9 non-interactive broker
├── bootstrap-broker.sh           # Cross-platform launcher
├── scaffold-copy.ps1             # Stage 10 plan-first scaffold builder
├── scaffold-copy.sh              # Cross-platform launcher
├── brownfield-import.ps1         # Stage 11 brownfield import generator
├── brownfield-import.sh          # Cross-platform launcher
├── factory/ci/                   # Stage 12 CI runner and source policies
├── factory/dogfood/              # Stage 13 dogfood orchestration and evidence
├── factory/release/              # Stage 14 attestation and promotion planning
├── dogfood-instance.ps1          # Stage 13 PowerShell entry point
├── dogfood-instance.sh           # Stage 13 strict Bash launcher
├── release-readiness.ps1         # Stage 14 PowerShell entry point
├── release-readiness.sh          # Stage 14 strict Bash launcher
├── USER-CHECKLIST.md             # Operator authentication, publication, and verification
├── TODO.md                       # Current phase plan
├── CHANGELOG.md                  # Completed work history
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
[USER-CHECKLIST.md](USER-CHECKLIST.md).

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

The stable GitHub context is `Factory CI / Factory CI`. The runner uses no
cloud credentials, initializes Terraform with backends disabled, and writes
`factory-ci-report.json` plus per-check logs.

### After Scaffold

Once the generated repository is published, the numbered workflows take over:

- `010-terraform-init.yml` initializes Terraform and validates the workload setup
- `020-rbac-validation.yml` audits service principal RBAC (also runs weekly)
- Subsequent pushes/PRs touching `terraform/**` trigger `terraform-plan.yml` (on PR) and `terraform-apply.yml` (on merge to `main`)

Each layer under `terraform/live/` deploys independently and in dependency order: `global` → `platform-connectivity` → `platform-management` → `workloads-prod` → `sandbox`.

---

## Optional Static Configuration Generator

`frontend/` is a standalone static page — open `frontend/index.html` in a browser, no server required. It lets you pick org name, region, network topology, policy assignments, and other options, then generates a `.tfvars` file you can download or copy. Feed that file into the Terraform layer it corresponds to (`terraform apply -var-file=your-file.tfvars`). See [docs/webapp/PLAN.md](docs/webapp/PLAN.md) for details.

---

## Key Features

### Firewall Choice
Select at deployment time via the `firewall_type` variable in the `platform-connectivity` layer: Azure Firewall (`azfw`), Palo Alto (`palo`), or Fortinet (`fortinet`).

### Sandbox with Auto-Expiry
- Sandbox resources require an `expiry_date` tag (`YYYY-MM-DD`)
- `Cleanup-ExpiredSandboxResources.ps1` validates the subscription is GUID-formatted and tagged `purpose=sandbox` before touching anything, supports `-DryRun` (default on), and enforces a max-deletion limit
- The sandbox module (`terraform/modules/sandbox/`) is feature-toggled off by default (`create_sandbox_rg = false`)

### Governance via Azure Policy
Policy baseline module enforces mandatory tagging, allowed locations, NSG requirements, TLS 1.2 minimum (Storage, App Service, Function Apps, MySQL, PostgreSQL — API Management coverage not yet implemented, see [TODO.md](TODO.md)), and sandbox isolation rules.

### GitOps Workflow
- PR opened against `main` touching `terraform/**` → `terraform plan` runs, posts results to the PR
- PR merged → `terraform apply` runs per-layer, sequentially (`max-parallel: 1`)
- Production layers use a GitHub environment gate; sandbox uses its own environment

---

## Current Known Issues

See [TODO.md](TODO.md) for the full, current list. Highlights as of 2026-07-01:

- CI/CD pipeline has no recorded successful run yet — root cause (a missing OIDC federated credential for `pull_request`-triggered runs) has been fixed in code; live verification is pending
- Backend is currently `azurerm` native storage everywhere except the bootloader and workflow `010`, which assume Terraform Cloud — migration tracked as [GitHub Issue #11](https://github.com/saulpatinojr/HCW-Plan_LZDeployment/issues/11)
- 6 of 11 Terraform modules are missing a `README.md`
- Two modules (`keyvault-cmk`, `sentinel-siem`) are scaffold-only stubs with no real resources yet
- 4 utility scripts (`Configure-DeploymentOptions.ps1`, `Invoke-BulkOperations.ps1`, `Validate-ALZDeployment.ps1`, `Verify-CostAccuracy.ps1`) exist but aren't currently called from anywhere in the pipeline — their disposition is tracked in [TODO.md](TODO.md)

---

## Technology Stack

| Component | Technology | Version |
|---|---|---|
| IaC | Terraform | 1.9+ |
| Cloud Provider | Azure | azurerm provider ~> 4.0 |
| CI/CD | GitHub Actions | OIDC-authenticated |
| State Backend | Azure Storage (native), migrating to Terraform Cloud | — |
| Governance | Azure Policy | Built-in + custom policy definitions |
| Config Generator | Static HTML/CSS/vanilla JS | No backend, no build step |

---

## Documentation

- **[TODO.md](TODO.md)** — current phase plan and open work
- **[CHANGELOG.md](CHANGELOG.md)** — completed work history, with verification notes
- **[docs/webapp/PLAN.md](docs/webapp/PLAN.md)** — static config-generator build plan
- **[terraform/modules/\*/README.md](terraform/modules/)** — per-module usage docs (where they exist — see Known Issues)

---

## Naming Convention

Follows [Microsoft CAF naming standards](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming):

- Management Groups: `mg-{scope}`
- Resource Groups: `rg-{scope}-{region}-{env}-{nn}`
- Resources: `{type}-{name}-{region}-{env}-{nn}`

## Tagging Strategy

Mandatory tags enforced via policy baseline: `owner`, `application`, `environment` (`prod`/`nonprod`/`sandbox`), `cost_center`. Sandbox resources additionally require `expiry_date`.
