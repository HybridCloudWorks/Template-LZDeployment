# Management Groups Module

## Overview

Creates the landing zone's management group hierarchy — a root group with
`platform`, `landingzones`, and `sandbox` children — and moves the supplied
subscriptions into the group that owns them. Called by the `global` layer
(`terraform/live/global/main.tf`); every other layer's policy scoping depends
on the IDs this module outputs.

Hierarchy created:

```
mg-<org_prefix>-root
├── mg-<org_prefix>-platform        (identity, connectivity, management subs)
├── mg-<org_prefix>-landingzones    (workload prod / nonprod subs)
└── mg-<org_prefix>-sandbox         (sandbox sub)
```

Every subscription variable is optional: an empty string skips that
subscription's association (`count`-guarded), so the hierarchy can be built
before all subscriptions exist.

## Usage

From `terraform/live/global/main.tf`:

```hcl
module "management_groups" {
  source = "../../modules/management-groups"

  org_prefix                       = var.org_prefix
  identity_subscription_id         = var.identity_subscription_id
  connectivity_subscription_id     = var.connectivity_subscription_id
  management_subscription_id       = var.management_subscription_id
  workload_prod_subscription_id    = var.workload_prod_subscription_id
  workload_nonprod_subscription_id = var.workload_nonprod_subscription_id
  sandbox_subscription_id          = var.sandbox_subscription_id
}
```

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `org_prefix` | Organization prefix for naming | `string` | — | yes |
| `identity_subscription_id` | Subscription ID for Identity (→ platform MG) | `string` | `""` | no |
| `connectivity_subscription_id` | Subscription ID for Connectivity (→ platform MG) | `string` | `""` | no |
| `management_subscription_id` | Subscription ID for Management (→ platform MG) | `string` | `""` | no |
| `workload_prod_subscription_id` | Subscription ID for Production Workloads (→ landingzones MG) | `string` | `""` | no |
| `workload_nonprod_subscription_id` | Subscription ID for Non-Production Workloads (→ landingzones MG) | `string` | `""` | no |
| `sandbox_subscription_id` | Subscription ID for Sandbox (→ sandbox MG) | `string` | `""` | no |

## Outputs

| Name | Description |
|---|---|
| `root_mg_id` | Root management group ID |
| `platform_mg_id` | Platform management group ID |
| `landingzones_mg_id` | Landing Zones management group ID |
| `sandbox_mg_id` | Sandbox management group ID |
| `management_group_map` | Map of management group names to IDs |

## Cost Estimate

| Component | Monthly Cost (estimate) |
|---|---|
| Management groups | $0 |
| Subscription associations | $0 |
| **Total** | **$0/month** |

*Management groups and subscription associations are free Azure constructs.
The costs of a landing zone come from the resources deployed inside the
subscriptions, not from this module.*

## Notes

- Deleting a management group that still contains subscriptions fails; empty
  the group (or re-associate the subscriptions) first.
- The identity creating the root management group needs Management Group
  Contributor at tenant root scope.

## References

- [Azure management groups documentation](https://learn.microsoft.com/azure/governance/management-groups/overview)
- [`azurerm_management_group`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group)
