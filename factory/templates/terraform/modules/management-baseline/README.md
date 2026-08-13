# Management Baseline Module

## Overview

Provides the landing zone's central observability foundation: the shared Log
Analytics workspace every other layer sends diagnostics to, an Automation
Account for operational runbooks, a workspace-based Application Insights
instance, an alert Action Group with configurable email receivers, and a
metric alert on workspace ingestion volume. Called by the
`platform-management` layer (`terraform/live/platform-management/main.tf`).

The `log_analytics_workspace_id` output is the value the connectivity layer's
operators paste into their tfvars after this layer applies (the documented
placeholder loop-back — see contract #4 in
`docs/CROSS-DOMAIN-CONTRACTS.md`).

## What It Creates

- `rg-<org_prefix>-management` resource group
- `law-<org_prefix>-<region_code>` Log Analytics workspace (PerGB2018,
  configurable retention)
- `aa-<org_prefix>-<region_code>` Automation Account (Basic SKU)
- `appi-<org_prefix>-<region_code>` Application Insights (workspace-based,
  type `other`)
- `ag-<org_prefix>-<region_code>` Action Group with the supplied email
  receivers (common alert schema)
- `alert-log-ingestion-<org_prefix>` metric alert: workspace `Data Ingestion`
  total > 100 MB per 15-minute window (severity 2), routed to the Action Group

## Usage

From `terraform/live/platform-management/main.tf`:

```hcl
module "management_baseline" {
  source = "../../modules/management-baseline"

  org_prefix            = var.org_prefix
  location              = var.primary_region
  region_code           = var.primary_region_code
  log_retention_days    = var.log_retention_days
  alert_email_receivers = var.alert_email_receivers
  tags                  = local.common_tags
}
```

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `org_prefix` | Organization prefix for naming | `string` | — | yes |
| `student_resource_group_name` | Demo only. When set, deploy into this pre-existing resource group instead of creating one. Empty means create, the normal behaviour. | `string` | `""` | no |
| `location` | Azure region for management resources | `string` | — | yes |
| `region_code` | Short region code for naming (e.g., scus, neu) | `string` | — | yes |
| `log_retention_days` | Log Analytics retention in days (7–730, validated) | `number` | `30` | no |
| `alert_email_receivers` | Email receivers attached to the alert Action Group | `list(object({ name = string, email_address = string }))` | `[]` | no |
| `tags` | Common tags for all resources | `map(string)` | `{ Module = "management-baseline", Tier = "management" }` | no |

## Outputs

| Name | Description |
|---|---|
| `log_analytics_workspace_id` | Log Analytics workspace ID for reference by other modules |
| `log_analytics_workspace_name` | Log Analytics workspace name |
| `automation_account_id` | Automation Account ID |
| `automation_account_name` | Automation Account name |
| `application_insights_id` | Application Insights ID |
| `application_insights_instrumentation_key` | Application Insights instrumentation key (sensitive) |
| `action_group_id` | Alert Action Group ID |
| `resource_group_name` | Management resource group name |
| `management_summary` | Summary map of the resources created |

## Cost Estimate

| Component | Monthly Cost (estimate) |
|---|---|
| Log Analytics ingestion (~10–30 GB/month typical early usage) | ~$25–90 |
| Log Analytics retention beyond 31 days | $0 at the default 30 days |
| Automation Account (Basic, within 500 free job minutes) | ~$0–5 |
| Application Insights (workspace-based, billed as ingestion above) | included |
| Action Group email notifications | ~$0 |
| Metric alert (1 rule) | ~$0.10 |
| **Total** | **~$25–100/month** |

*Estimates only. Log ingestion dominates and scales with connected resources —
every diagnostic setting across the landing zone lands in this workspace.
Default alert threshold (100 MB / 15 min) exists to catch runaway ingestion
before it becomes a bill.*

## Notes

- With `alert_email_receivers = []` (the default) the Action Group exists but
  notifies no one — supply at least one receiver for production.
- Retention above 31 days adds a per-GB retention charge; the 7–730 bound is
  enforced by a validation block.

## References

- [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/)
- [Log Analytics workspace overview](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview)
- [Azure Automation pricing](https://azure.microsoft.com/pricing/details/automation/)
