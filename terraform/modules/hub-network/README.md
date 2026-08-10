# Hub Network Module

## Overview

Deploys one regional hub of the hub-and-spoke topology: the hub VNet with its
firewall, management, trust/untrust, gateway, and optional Bastion/DNS
resolver subnets, an Azure Firewall (or subnet placeholders for a Palo
Alto/Fortinet NVA), the spoke route table pointing at the firewall, and —
optionally — a Firewall Policy with Threat Intelligence, IDPS (Premium), and
diagnostics. Called once per region by the `platform-connectivity` layer
(`terraform/live/platform-connectivity/main.tf`); spokes consume its outputs
through that layer's remote state.

## What It Creates

**Always**
- `rg-hub-<region_code>-<environment>-01` resource group and hub VNet
- Subnets: `AzureFirewallSubnet`, firewall management, NVA trust/untrust,
  `GatewaySubnet`; optional `AzureBastionSubnet` and DNS resolver
  inbound/outbound subnets (placeholder toggles)
- Management NSG locked to `var.management_ip_ranges` (wildcards rejected by
  validation)
- Route table for spokes with default route to the firewall's private IP

**When `firewall_type = "azfw"`**
- Public IP and Azure Firewall (`Standard` or `Premium` tier, zonal)
- Diagnostic settings to `var.log_analytics_workspace_id` (skipped when empty)

**When `enable_firewall_threat_intel = true` (azfw only)**
- Azure Firewall Policy with Threat Intelligence
  (`var.firewall_threat_intel_mode`: `Off`/`Alert`/`Deny`, default `Alert`),
  allowlists, DNS proxy, and — on Premium — IDPS mode, signature overrides,
  traffic bypass, and optional TLS inspection
- Firewall Policy diagnostics and a scheduled-query alert on threat-intel hits
  routed to `var.security_action_group_ids`

**When `firewall_type = "palo"` or `"fortinet"`**
- No firewall resource is deployed; the trust/untrust subnets and
  `var.nva_trust_ip_placeholder` (defaults to the first usable trust-subnet
  host) reserve the layout until the NVA lands.

## Usage

From `terraform/live/platform-connectivity/main.tf`:

```hcl
module "hub_primary" {
  source = "../../modules/hub-network"

  region                     = var.primary_region
  region_code                = var.primary_region_code
  environment                = "prod"
  hub_address_space          = var.primary_hub_address_space
  firewall_type              = var.firewall_type
  azfw_tier                  = var.azfw_tier
  firewall_threat_intel_mode = var.firewall_threat_intel_mode
  nva_trust_ip_placeholder   = var.primary_nva_trust_ip
  deploy_bastion_placeholder = var.deploy_bastion
  deploy_dns_placeholder     = var.deploy_dns
  management_ip_ranges       = var.management_ip_ranges
  availability_zones         = var.primary_availability_zones
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = local.common_tags
}
```

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `region` | Azure region | `string` | — | yes |
| `region_code` | Short region code (e.g., scus, ncus) | `string` | — | yes |
| `environment` | Environment name | `string` | `"prod"` | no |
| `hub_address_space` | Address space for hub VNet | `string` | — | yes |
| `firewall_type` | `azfw`, `palo`, or `fortinet` (validated) | `string` | — | yes |
| `azfw_tier` | Azure Firewall tier: `Standard` or `Premium` | `string` | `"Standard"` | no |
| `nva_trust_ip_placeholder` | Placeholder IP for NVA trust interface | `string` | `null` (derived) | no |
| `deploy_bastion_placeholder` | Create Bastion subnet placeholder | `bool` | `true` | no |
| `deploy_dns_placeholder` | Create DNS resolver subnet placeholders | `bool` | `true` | no |
| `management_ip_ranges` | CIDRs allowed to reach firewall management; `*`/`0.0.0.0/0` rejected | `list(string)` | — | yes |
| `availability_zones` | Zones for zonal resources | `list(string)` | `["1", "2", "3"]` | no |
| `tags` | Tags to apply to all resources | `map(string)` | — | yes |
| `enable_firewall_threat_intel` | Enable Azure Firewall Threat Intelligence (Firewall Policy) | `bool` | `false` | no |
| `firewall_threat_intel_mode` | `Off`, `Alert`, or `Deny` | `string` | `"Alert"` | no |
| `firewall_threat_intel_allowlist_ips` | IPs bypassing Threat Intelligence | `list(string)` | `[]` | no |
| `firewall_threat_intel_allowlist_fqdns` | FQDNs bypassing Threat Intelligence | `list(string)` | `[]` | no |
| `firewall_dns_servers` | Custom DNS servers for firewall DNS proxy | `list(string)` | `[]` | no |
| `firewall_idps_mode` | IDPS mode (Premium): `Off`, `Alert`, `Deny` | `string` | `"Alert"` | no |
| `firewall_idps_signature_overrides` | IDPS signature overrides | `list(object)` | `[]` | no |
| `firewall_idps_traffic_bypass` | IDPS traffic bypass rules | `list(object)` | `[]` | no |
| `firewall_enable_tls_inspection` | TLS inspection (Premium only) | `bool` | `false` | no |
| `firewall_tls_certificate_key_vault_secret_id` | Key Vault secret for TLS inspection cert | `string` | `""` | no |
| `log_analytics_workspace_id` | Workspace for diagnostics; empty disables diagnostics/alerts | `string` | `""` | no |
| `private_endpoint_subnet_prefix` | CIDR for the hub private-endpoint subnet, supplied from your own address plan (no cidrsubnet index is free under both firewall layouts). Null creates no subnet. | `string` | `null` | no |
| `enable_threat_intel_alerts` | Alert on threat-intelligence hits | `bool` | `true` | no |
| `security_action_group_ids` | Action Groups for security alerts | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|---|---|
| `hub_vnet_id` / `hub_vnet_name` | Hub VNet ID and name (consumed by spoke peering) |
| `resource_group_name` | Hub resource group name |
| `firewall_private_ip` | Firewall private IP for spoke UDRs |
| `route_table_id` | Route table ID for spoke associations |
| `gateway_subnet_id` | Gateway subnet ID |
| `firewall_type` | Deployed firewall type |
| `firewall_policy_id` | Firewall Policy ID (null unless azfw + threat intel) |
| `firewall_threat_intel_mode` | Configured mode, or `Disabled` |
| `firewall_idps_mode` | IDPS mode (Premium), or `Not Available` |
| `firewall_diagnostics_enabled` | Whether threat-intel diagnostics are enabled |
| `nsg_ids` | Map of hub NSG role (`fw_mgmt`) to NSG ID, for `nsg-flow-logs`. Empty map when no NVA firewall is deployed |

## Cost Estimate

| Component | Monthly Cost (estimate) |
|---|---|
| Azure Firewall Standard (deployment ~730 h) | ~$900–950 |
| Azure Firewall Premium (instead of Standard) | ~$1,700–1,800 |
| Firewall data processing | ~$16 per TB |
| Public IP (static) | ~$4 |
| VNet, subnets, NSG, route table | $0 |
| Log Analytics ingestion (firewall logs, volume-dependent) | ~$25–150 |
| **Total (azfw Standard, typical)** | **~$950–1,100/month per hub** |

*Estimates only. The firewall's hourly meter dominates and runs whether or not
traffic flows; a DR-region hub doubles it. `palo`/`fortinet` deployments incur
no firewall cost here — NVA compute and licensing are provisioned outside this
module.*

## Notes

- With `enable_firewall_threat_intel = false` (the default) the firewall runs
  without a Firewall Policy; enabling it later replaces the firewall's
  classic-rule configuration with the policy attachment.
- Bastion and DNS resolver subnets are placeholders — this module reserves the
  address space but deploys neither service.

## References

- [Azure Firewall pricing](https://azure.microsoft.com/pricing/details/azure-firewall/)
- [Azure Firewall Threat Intelligence](https://learn.microsoft.com/azure/firewall/threat-intel)
- [Azure Firewall Premium IDPS](https://learn.microsoft.com/azure/firewall/premium-features)
