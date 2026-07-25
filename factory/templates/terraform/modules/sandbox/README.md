# Sandbox Module

Azure Verified Module (AVM) compliant sandbox resource group module for temporary or permanent sandbox deployments.

## Overview

This module provides a reusable, AVM-compliant sandbox resource group with the following characteristics:

- **Feature Toggle**: Sandbox resources are not created by default
- **Lifecycle Management**: Supports temporary and permanent sandboxes with optional expiry dates
- **Tag-Based Cleanup**: Tags enable external automation (Azure Policy, Azure Automation) to detect and clean up expired sandboxes
- **Drift Detection**: Terraform automatically detects manual changes via workflow 100 (terraform plan)
- **Immutable**: Desired state is always enforced via Terraform

## Features

- ✅ AVM-compliant (Microsoft Azure Verified Modules)
- ✅ Feature toggle pattern (safe defaults)
- ✅ Lifecycle tracking (temporary/permanent)
- ✅ Expiry date support (ISO 8601)
- ✅ Owner tracking (optional)
- ✅ Drift detection (terraform plan)
- ✅ Anti-corruption outputs (discrete values)
- ✅ Input validation (types, formats, values)

## Usage

### Basic Example (Temporary Sandbox)

```hcl
module "sandbox" {
  source = "../../modules/sandbox"

  create_sandbox_rg = true
  resource_group_name = "rg-sandbox-dev-eastus"
  location = "eastus"

  sandbox_tags = {
    environment  = "sandbox"
    lifecycle    = "temporary"
    created_date = "2026-06-30"
    expiry_date  = "2026-07-30"
    owner        = "platform-team"
  }
}
```

### Disabled by Default

```hcl
module "sandbox" {
  source = "../../modules/sandbox"

  # create_sandbox_rg defaults to false
  # Uncomment and set to true to enable sandbox creation
}
```

### In terraform.tfvars

```hcl
create_sandbox_rg = true

resource_group_name = "rg-sandbox-test-eastus"
location = "eastus"

sandbox_tags = {
  environment  = "sandbox"
  lifecycle    = "temporary"
  created_date = "2026-06-30"
  expiry_date  = "2026-07-30"  # Optional: triggers cleanup after this date
  owner        = "dev-team"     # Optional: owner for follow-up
}
```

## Tag Semantics

### Required Tags

| Tag | Values | Purpose |
|-----|--------|---------|
| `environment` | `sandbox`, `dev`, `test`, etc. | Environment classification |
| `lifecycle` | `temporary`, `permanent` | Cleanup eligibility |
| `created_date` | ISO 8601 date (YYYY-MM-DD) | Creation timestamp |

### Optional Tags

| Tag | Format | Purpose |
|-----|--------|---------|
| `expiry_date` | ISO 8601 date (YYYY-MM-DD) | External cleanup trigger |
| `owner` | Team or person name | Responsible party |

### Automatic Tags

| Tag | Value | Purpose |
|-----|-------|---------|
| `managed_by` | `terraform` | Indicates IaC-managed resource |
| `module` | `sandbox` | Module identifier |

## Cleanup Strategy

This module enables three cleanup approaches:

### 1. Terraform-Managed Cleanup
```hcl
# Simply remove from terraform code
# terraform plan detects deletion
# terraform apply removes resource
```

### 2. Tag-Based External Cleanup
Azure Policy or Azure Automation can detect sandboxes where:
- `lifecycle == "temporary"` AND `expiry_date < today()`

Then trigger resource group deletion.

### 3. Manual Cleanup
```bash
# List temporary sandboxes past expiry
az group list --query "?tags.lifecycle=='temporary' && tags.expiry_date<'2026-07-01'" -o table

# Delete specific sandbox
az group delete --name rg-sandbox-test-eastus --no-wait
```

## Drift Detection

This module integrates with the landing zone CI/CD pipeline:

### Workflow 100: Terraform Plan (Drift Detection)

```
Developer commit → PR → Workflow 100 runs
  ↓
  terraform plan detects:
    - Manual changes (via portal, CLI, etc.)
    - Configuration drift
    - Required corrections
  ↓
  PR comments show required actions
  ↓
  Developer can:
    A) Accept drift (update terraform code)
    B) Discard drift (terraform apply reverts)
```

### Workflow 200: Terraform Apply (Enforcement)

```
PR merged to main → Workflow 200 runs
  ↓
  terraform apply enforces desired state
  ↓
  Any manual changes are corrected
  ↓
  State versioned in Terraform Cloud
  ↓
  Full audit trail in git + TFC
```

## Migration from PowerShell

### Before (PowerShell)

```powershell
# Cleanup-ExpiredSandboxResources.ps1
Remove-AzResourceGroup -Name "rg-sandbox-*" -Force

# Issues:
# ❌ Not tracked in IaC
# ❌ No drift detection
# ❌ No rollback capability
# ❌ Labor-intensive
```

### After (Terraform)

```hcl
# terraform/live/sandbox/main.tf
module "sandbox" {
  source = "../../modules/sandbox"
  
  create_sandbox_rg = false  # Default: safe
  # Uncomment to enable
  
  # Benefits:
  # ✅ Tracked in git + TFC
  # ✅ Drift detection automatic
  # ✅ Immutable state
  # ✅ Self-maintaining
}
```

## AVM Compliance

This module meets Azure Verified Modules (AVM) requirements:

- ✅ **TFNFR18**: Precise variable types (not `any`)
- ✅ **TFNFR17**: Detailed variable descriptions
- ✅ **TFNFR20**: Collections have `nullable = false`
- ✅ **TFNFR7**: Feature toggle via `count`
- ✅ **TFNFR25**: Terraform version constraints
- ✅ **TFNFR26**: Required provider versions
- ✅ **TFFR2**: Anti-corruption outputs (discrete values)
- ✅ **TFNFR32**: Locals alphabetically ordered
- ✅ **TFNFR34**: Feature toggle for optional resources

## Validation

### Format Check

```bash
terraform -chdir=terraform/modules/sandbox fmt -check
```

### Syntax Validation

```bash
terraform -chdir=terraform/modules/sandbox validate
```

### Plan

```bash
terraform -chdir=terraform/live/sandbox plan -out=tfplan
```

### Apply

```bash
terraform -chdir=terraform/live/sandbox apply tfplan
```

## Outputs

| Output | Description |
|--------|-------------|
| `sandbox_resource_group_id` | Azure Resource ID of sandbox resource group |
| `sandbox_resource_group_name` | Name of sandbox resource group |
| `sandbox_resource_group_location` | Azure region of sandbox resource group |

## Security Considerations

- **Safe Default**: Sandboxes not created by default (`create_sandbox_rg = false`)
- **Immutable**: Once applied, desired state is always enforced
- **Auditable**: Every change tracked in git and Terraform Cloud
- **Drift Protected**: Automated detection of unauthorized changes
- **Lifecycle Managed**: Tags enable automated cleanup of temporary resources

## Cost Optimization

Temporary sandboxes can be automatically cleaned up based on expiry date:

1. **Tag sandboxes** with `lifecycle = "temporary"` and `expiry_date`
2. **Create Azure Policy** or **Azure Automation runbook** to detect and delete expired sandboxes
3. **Avoid storage waste** from forgotten test environments

## Further Reading

- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
- [AVM Terraform Specifications](https://azure.github.io/Azure-Verified-Modules/specs/terraform/)
- [Terraform Cloud Backend Configuration](https://www.terraform.io/cloud-docs)
