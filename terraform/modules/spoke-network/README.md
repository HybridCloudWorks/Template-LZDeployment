# Spoke Network Module

## Overview

Creates one workload spoke: a VNet with `app`, `data`, and private-endpoint
subnets, deny-by-default NSGs, an optional forced-tunnel route to the hub
firewall, and bidirectional VNet peering with the hub. Called by the workload
layers (`terraform/live/workloads-prod/main.tf` is the reference caller).

**Provider requirement**: this module declares
`configuration_aliases = [azurerm.hub]` because the hub side of the peering
must be created in the connectivity subscription that owns the hub VNet.
Every caller must pass a `providers` map (see Usage) — omitting it fails at
`terraform validate`. This is cross-domain contract #5 in
`docs/CROSS-DOMAIN-CONTRACTS.md`.

## What It Creates

- `rg-<spoke_name>-<region_code>-<environment>-01` resource group and spoke VNet
- Subnets: `app`, `data`, `pe` (private endpoints)
- NSGs on all three subnets. `app` and `data` carry, in priority order:
  caller rules from `var.additional_security_rules` (priorities 100–4094,
  validated), an `AllowAzureLoadBalancerInbound` rule at 4095 (so health
  probes keep working), and a `DenyAllInbound` floor at 4096
- Route tables on the app and data subnets with a `0.0.0.0/0` default route to
  `var.firewall_private_ip` when `enable_forced_tunneling = true`
  (BGP propagation disabled); the `pe` subnet is not forced-tunneled
- VNet peering spoke→hub (default provider) and hub→spoke (`azurerm.hub`
  provider) when `enable_hub_peering = true`

## Usage

From `terraform/live/workloads-prod/main.tf`:

```hcl
provider "azurerm" {
  alias           = "hub"
  subscription_id = var.connectivity_subscription_id
  features {}
}

module "spoke_prod_primary" {
  source = "../../modules/spoke-network"

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.hub
  }

  spoke_name              = "prod-app"
  region                  = var.primary_region
  region_code             = var.primary_region_code
  environment             = "prod"
  spoke_address_space     = var.primary_spoke_address_space
  enable_hub_peering      = true
  hub_vnet_id             = local.primary_hub.vnet_id
  hub_vnet_name           = local.primary_hub.vnet_name
  hub_resource_group_name = local.primary_hub.resource_group_name
  enable_forced_tunneling = true
  firewall_private_ip     = local.primary_hub.firewall_private_ip
  use_remote_gateways     = false
  tags                    = local.common_tags
}
```

When no hub exists, satisfy the alias with the spoke's own provider and
disable peering: `providers = { azurerm = azurerm, azurerm.hub = azurerm }`
with `enable_hub_peering = false`.

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `spoke_name` | Name identifier for the spoke (e.g., `prod-app`) | `string` | — | yes |
| `student_resource_group_name` | Demo only. When set, deploy into this pre-existing resource group instead of creating one. Empty means create, the normal behaviour. | `string` | `""` | no |
| `region` | Azure region | `string` | — | yes |
| `region_code` | Short region code (e.g., scus, ncus) | `string` | — | yes |
| `environment` | Environment name | `string` | — | yes |
| `spoke_address_space` | Address space for the spoke VNet | `string` | — | yes |
| `enable_hub_peering` | Enable peering to hub VNet | `bool` | `true` | no |
| `hub_vnet_id` | Hub VNet resource ID | `string` | `""` | no |
| `hub_vnet_name` | Hub VNet name | `string` | `""` | no |
| `hub_resource_group_name` | Hub resource group name | `string` | `""` | no |
| `enable_forced_tunneling` | Default route to the firewall | `bool` | `true` | no |
| `firewall_private_ip` | Firewall private IP for the UDR next hop | `string` | `"10.0.1.4"` | no |
| `use_remote_gateways` | Use the hub's VPN/ER gateways | `bool` | `false` | no |
| `additional_security_rules` | Extra NSG rules for app/data subnets; priorities 100–4094 (validated) | `list(object)` | `[]` | no |
| `tags` | Tags to apply to all resources | `map(string)` | — | yes |

## Outputs

| Name | Description |
|---|---|
| `spoke_vnet_id` / `spoke_vnet_name` | Spoke VNet ID and name |
| `resource_group_name` | Spoke resource group name |
| `app_subnet_id` | Application subnet ID |
| `data_subnet_id` | Data subnet ID |
| `pe_subnet_id` | Private endpoint subnet ID |

## Cost Estimate

| Component | Monthly Cost (estimate) |
|---|---|
| VNet, subnets, NSGs, route table | $0 |
| VNet peering data transfer (~500 GB/month, both directions) | ~$10 |
| Forced-tunnel traffic (firewall data processing, billed at the hub) | ~$16 per TB |
| **Total (typical light spoke)** | **~$10–30/month** |

*Estimates only. Spoke constructs are free; cost is entirely traffic-driven
(peering ingress+egress ≈ $0.01/GB each way, plus hub firewall processing for
forced-tunneled traffic) and scales with workload volume.*

## Notes

- Peering with `use_remote_gateways = true` requires a gateway to exist in the
  hub; the hub-network module only reserves `GatewaySubnet`.
- Hub-side peering (`azurerm.hub`) needs the deploying identity to hold
  Network Contributor rights in the connectivity subscription.
- The `pe` subnet NSG ships with no custom rules — Azure's default rules
  apply there.

## References

- [VNet peering pricing](https://azure.microsoft.com/pricing/details/virtual-network/)
- [Hub-spoke network topology](https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke)
- [`azurerm_virtual_network_peering`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering)
