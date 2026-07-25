# Customer-Managed Keys (CMK) Module - OPTIONAL

## ⚠️ Status: Module Scaffold - Implementation TBD

This module is **not deployed by default** due to additional cost and complexity. Enable it when your compliance requirements explicitly mandate customer-managed encryption keys.

## Overview

This module provisions **Azure Key Vault with Premium (HSM-backed) keys** for customer-managed encryption of Azure resources, providing full control over encryption key lifecycle.

## What You Get

✅ **Key Vault Premium** - HSM-backed key storage  
✅ **Customer-Managed Keys** - Full key lifecycle control  
✅ **State Storage Encryption** - Terraform state encrypted with CMK  
✅ **Backup Vault Encryption** - Recovery Services encrypted with CMK  
✅ **Storage Account Encryption** - Data encrypted with CMK  
✅ **Key Rotation** - Automated key versioning and rotation  
✅ **Audit Logs** - Comprehensive key access logging

## Cost Estimate

| Component | Monthly Cost |
|---|---|
| **Key Vault Premium** | ~$125 |
| **Key Operations** (typical usage) | ~$50 |
| **Storage (encrypted)** | +$75 premium |
| **Total** | **~$250/month** |

## When to Enable

**Enable CMK if:**
- ✅ Compliance explicitly requires customer-managed keys (HIPAA High Trust, FedRAMP High)
- ✅ Need detailed audit trail for all key access
- ✅ Require custom key rotation policies
- ✅ Multi-tenant environment needing key isolation
- ✅ Regulatory requirement for key revocation capability

**Do NOT enable if:**
- ❌ Basic Azure encryption at rest is sufficient (it's already enabled!)
- ❌ Compliance doesn't mandate CMK
- ❌ Budget constraints are tight
- ❌ Operational complexity is a concern

## What's Already Encrypted (Without CMK)

Azure provides **encryption at rest by default** using Microsoft-managed keys for:
- ✅ Storage Accounts (Terraform state) - AES-256
- ✅ Backup Vaults - AES-256
- ✅ Azure SQL databases - TDE
- ✅ Virtual Machine disks - AES-256

**CMK gives you control, not additional encryption** - data is already encrypted!

## Features This Module Will Provide

### 1. Key Vault Premium
```hcl
resource "azurerm_key_vault" "cmk" {
  name                       = "kv-cmk-${var.region_code}-${var.environment}"
  sku_name                   = "premium"  # HSM-backed
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
}
```

### 2. Encryption Keys
- Terraform state storage encryption key
- Backup vault encryption key
- Custom application encryption keys
- Automatic versioning and rotation

### 3. Managed Identity Integration
- System-assigned identities for Key Vault access
- RBAC role assignments (Key Vault Crypto Officer, Crypto User)
- Cross-subscription key access support

### 4. Monitoring & Alerts
- Key access audit logs
- Failed access attempts
- Key rotation tracking
- Expiration warnings

## Deployment Steps (When Ready)

### 1. Enable in Configuration

Copy `.azure/deployment-options.yaml.example` to `.azure/deployment-options.yaml` (if you haven't already) and edit it:
```yaml
modules:
  cmk:
    enabled: true  # Change from false
```

Or run the interactive script:
```powershell
.\scripts\Configure-DeploymentOptions.ps1
```

### 2. Review Prerequisites

- [ ] Confirm compliance requirement for CMK
- [ ] Budget approved for $250/month recurring cost
- [ ] Key Vault Premium quota available in region
- [ ] Operational team trained on key management

### 3. Deploy Module

```bash
terraform init
terraform plan -target=module.keyvault_cmk -out=cmk.tfplan
terraform apply cmk.tfplan
```

### 4. Migrate Resources to CMK

After deployment, existing resources must be migrated:
1. Terraform state storage (recreate with CMK)
2. Backup vaults (update encryption settings)
3. Storage accounts (rotate to CMK)

**⚠️ Warning**: Migration requires downtime for some resources!

## Compliance Mapping

| Framework | CMK Requirement |
|---|---|
| **HIPAA** | Recommended, not required |
| **HIPAA High Trust** | ✅ **Required** |
| **PCI-DSS 4.0** | Recommended, not required |
| **FedRAMP Moderate** | Recommended |
| **FedRAMP High** | ✅ **Required** |
| **ISO 27001** | Recommended, not required |
| **SOC 2** | Recommended, not required |

## Key Rotation Policy

**Automatic rotation** (when module is implemented):
- Terraform state keys: 90 days
- Backup vault keys: 90 days
- Application keys: 180 days (configurable)

**Manual rotation triggers**:
- Security incident
- Personnel changes
- Compliance audit requirement

## Security Best Practices

✅ **Enable purge protection** - Prevents accidental key deletion  
✅ **Use RBAC** - Least privilege access to keys  
✅ **Enable soft delete** - 90-day recovery window  
✅ **Separate key vaults** - Production vs non-production  
✅ **Monitor key access** - Alert on unusual patterns  
✅ **Backup keys** - Export to secure offline storage  
✅ **Test key revocation** - Ensure recovery procedures work

## Trade-offs

### Pros
✅ Full control over encryption keys  
✅ Ability to revoke access instantly  
✅ Compliance checkbox for CMK mandate  
✅ Detailed audit trail  
✅ Custom rotation policies

### Cons
❌ Additional cost ($250/month)  
❌ Operational complexity  
❌ Key management responsibility  
❌ Potential for misconfiguration  
❌ Backup/recovery more complex

## Alternative: Azure-Managed Encryption

**Already enabled by default** - no action needed:
- ✅ AES-256 encryption at rest
- ✅ Transparent to applications
- ✅ No additional cost
- ✅ Automatic key rotation
- ✅ Managed by Microsoft

**Use this unless CMK is explicitly required by compliance.**

## Implementation Timeline

**Phase 2 Optional** (On-demand):
- Effort: 16 hours
- Cost: $250/month recurring
- Risk reduction: +5% (compliance coverage)

**Recommended approach**:
1. Deploy core Phase 2 tasks first (TLS, Firewall, Flow Logs)
2. Evaluate CMK requirement during compliance audit
3. Enable CMK only if mandated

## Next Steps

1. ✅ **Review compliance requirements** - Is CMK mandated?
2. ✅ **Budget approval** - $250/month recurring
3. ⏳ **Module implementation** - TBD when needed
4. ⏳ **Operational training** - Key management procedures
5. ⏳ **Migration planning** - Downtime windows for existing resources

## References

- [Azure Key Vault CMK Documentation](https://learn.microsoft.com/en-us/azure/key-vault/general/customer-managed-keys)
- [Storage Account CMK](https://learn.microsoft.com/en-us/azure/storage/common/customer-managed-keys-overview)
- [Backup Vault CMK](https://learn.microsoft.com/en-us/azure/backup/encryption-at-rest-with-cmk)

## Phase 2 Task Status

- ⚠️ **Task 2.1**: Customer-Managed Keys (CMK) - **OPTIONAL MODULE**  
- **Status**: Scaffold created, implementation deferred  
- **Effort**: 16 hours (when enabled)  
- **Cost**: $250/month  
- **Decision**: Enable explicitly via deployment options configuration

---

**💡 To enable this module**: Run `.\scripts\Configure-DeploymentOptions.ps1` and set `cmk.enabled = true`
