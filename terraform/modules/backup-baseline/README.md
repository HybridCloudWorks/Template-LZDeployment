# Backup Baseline Module

## Overview

Deploys the per-region backup foundation: a Recovery Services Vault (VMs,
Azure Files, SQL-in-VM workloads), a Data Protection Backup Vault (newer
workload types such as blobs and disks), and a dedicated Log Analytics
workspace wired to the Recovery Services Vault's diagnostic categories.
Called once per region by the `platform-management` layer
(`terraform/live/platform-management/main.tf`).

## What It Creates

- `rg-backup-<region_code>-<environment>-01` resource group
- `rsv-platform-<region_code>-<environment>-01` Recovery Services Vault
  (Standard SKU, configurable storage redundancy)
- `bv-platform-<region_code>-<environment>-01` Backup Vault
  (`VaultStore` datastore, configurable redundancy)
- `log-backup-<region_code>-<environment>-01` Log Analytics workspace
  (PerGB2018, 30-day retention)
- Diagnostic settings streaming the vault's backup report, core backup, jobs,
  alerts, policy, and storage logs plus Health metrics to that workspace

**This module provisions the vaults only.** Backup policies and protected
items (which VM/share/database gets backed up, and on what schedule) are not
created here — they belong to the workload that owns the resource.

## Usage

From `terraform/live/platform-management/main.tf` (called once per region):

```hcl
module "backup_primary" {
  source = "../../modules/backup-baseline"

  region                  = var.primary_region
  region_code             = var.primary_region_code
  environment             = "prod"
  storage_redundancy      = "GeoRedundant"
  backup_vault_redundancy = "GeoRedundant"
  tags                    = local.common_tags
}
```

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `region` | Azure region | `string` | — | yes |
| `region_code` | Short region code (e.g., scus, ncus) | `string` | — | yes |
| `environment` | Environment name | `string` | `"prod"` | no |
| `storage_redundancy` | Recovery Services Vault storage mode (`GeoRedundant`, `LocallyRedundant`, `ZoneRedundant`) | `string` | `"GeoRedundant"` | no |
| `backup_vault_redundancy` | Backup Vault redundancy (`GeoRedundant`, `LocallyRedundant`, `ZoneRedundant`) | `string` | `"GeoRedundant"` | no |
| `tags` | Tags to apply to all resources | `map(string)` | — | yes |

## Outputs

| Name | Description |
|---|---|
| `recovery_services_vault_id` | Recovery Services Vault ID |
| `backup_vault_id` | Backup Vault ID |
| `resource_group_name` | Backup resource group name |

## Cost Estimate

| Component | Monthly Cost (estimate) |
|---|---|
| Recovery Services Vault (empty) | $0 |
| Backup Vault (empty) | $0 |
| Log Analytics workspace (diagnostics only, low volume) | ~$5–15 |
| **Total with no protected items** | **~$5–15/month per region** |
| Per protected VM (instance fee + GRS storage, typical) | ~$15–40/month each |

*Estimates only. Vaults are free until items are protected; real cost is
driven by protected-instance fees and backup storage consumption
(GRS roughly doubles LRS storage cost). Two regions run two of everything.*

## Notes

- `GeoRedundant` vault storage cannot be changed after the first item is
  protected — pick redundancy before onboarding workloads.
- Deleting the module requires the vaults to be empty (no protected items,
  soft-delete cleared); otherwise `terraform destroy` fails.

## References

- [Azure Backup pricing](https://azure.microsoft.com/pricing/details/backup/)
- [Recovery Services vault overview](https://learn.microsoft.com/azure/backup/backup-azure-recovery-services-vault-overview)
- [Backup vault overview](https://learn.microsoft.com/azure/backup/backup-vault-overview)
