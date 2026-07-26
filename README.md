# HCW Azure Landing Zone Deployment

## Overview

This repository is the Landing Zone Factory. It renders a self-contained landing
zone repository from `lz-config.json`, discovers existing tenant state, and uses
the Stage 9 broker to reconcile external prerequisites before Terraform runs.

**How it works**:

1. `site/` exports the versioned `lz-config.json` contract.
2. `factory/discovery/` produces a read-only readiness report and
   `discovery-inventory.json`.
3. `factory/renderer/` emits Terraform, workflows, documentation, and
   `USER-CHECKLIST.md`.
4. `bootstrap-broker.ps1` / `.sh` plans by default and idempotently reconciles
   Entra, RBAC, GitHub, and backend prerequisites only in apply mode.

> **Status**: The CI/CD pipeline has known reliability issues currently being fixed — see [TODO.md](TODO.md) before relying on it for a real deployment.

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
├── USER-CHECKLIST.md             # Operator-owned authentication and live verification
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

### After Bootstrap

Once the bootstrap PR is merged, the numbered workflows take over:

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
