# NSG Flow Logs + Traffic Analytics Module

## Overview

This Terraform module enables **NSG Flow Logs** and **Traffic Analytics** for Azure Network Security Groups (NSGs), providing comprehensive network monitoring and security insights.

## Features

✅ **NSG Flow Logs Version 2** - Detailed network flow information  
✅ **Traffic Analytics** - ML-powered network insights and visualization  
✅ **RAGZRS Storage** - Geo-redundant flow log storage  
✅ **Private Endpoint** - Secure storage access without public internet  
✅ **Automated Alerts** - High traffic and denied traffic detection  
✅ **Long-term Retention** - Configurable retention (default 90 days)  
✅ **Security Monitoring** - Track denied flows for potential threats

## What You Get

### Flow Logs
- **Version 2 flow logs** with enhanced metadata
- Source/destination IP, port, protocol
- Allow/deny decision from NSG rules
- Flow statistics (bytes, packets)
- Stored in geo-redundant storage (RAGZRS)

### Traffic Analytics
- **Network topology visualization** 
- **Top talkers** - Most active endpoints
- **Denied flows** - Security threat indicators
- **Geographic traffic map**
- **Application protocols** - HTTP, SSH, RDP usage
- **Anomaly detection** - Unusual traffic patterns

### Monitoring & Alerts
1. **High Traffic Alert** - Triggers when traffic exceeds threshold (default 100 GB)
2. **Denied Traffic Spike Alert** - Potential attack or misconfiguration (default 1,000 denied flows)

## Scope: Explicit NSG List — No Auto-Discovery

This module does **not** discover NSGs. It enables flow logs only for the
NSGs explicitly passed in `var.nsg_ids` (default `{}` — passing nothing
deploys the storage/analytics scaffolding but logs zero NSGs). Every
`terraform/live/*` caller must enumerate each NSG it creates into `nsg_ids`;
an NSG added to a spoke or hub without a matching `nsg_ids` entry silently
has no flow logs.

As of 2026-08-09 (decision 0009) `terraform/live/workloads-prod` instantiates
this module **twice, once per region**, each `count`-gated on
`var.enable_nsg_flow_logs` which **defaults to `false`**, and each fed from
`spoke-network`'s `nsg_ids` map output rather than hand-maintained IDs.

`terraform/live/platform-connectivity` adds one instance per hub region,
covering the hub's `fw_mgmt` NSG (`hub-network`'s `nsg_ids` output), on the
same default-off `enable_nsg_flow_logs` gate. Network Watcher is regional
**and per-subscription**, which is why hub NSGs must be covered from the
connectivity layer and spoke NSGs from the workload layers — neither call can
reach the other's NSGs.

**Names must be distinct.** Storage account names are globally unique but the
composed default (`stflowlogs<region_code><environment>`) is not unique per
call, so any caller creating a second instance in a region and environment
already served must pass `storage_account_name`. The connectivity instances do
exactly that (`stflowlogshub<region_code>prod`), which is what lets them
coexist with `workloads-prod`'s `stflowlogs<region_code>prod` in the same
region and environment. Two instances left on the default in one
`(region, environment)` plan clean and then fail at apply on the name.

## Cost

The old version of this section quoted a flat **~$200/month** for five NSGs.
That number is withdrawn: it priced a per-GB meter by NSG count, which is the
wrong unit. Cost here is driven almost entirely by **how much traffic the
NSGs see**, not by how many of them there are. The same estate can bill $15
or $800 a month with the identical Terraform.

### What actually bills

Four meters, in the order they consume a flow record, plus the alert rules:

| # | Meter | Unit | Gated by |
|---|---|---|---|
| 1 | Network Watcher flow-log collection | per GB collected | always on when the module runs |
| 2 | Traffic Analytics processing | per GB processed (rate varies with `traffic_analytics_interval`) | `enable_traffic_analytics` |
| 3 | Log Analytics ingestion of `AzureNetworkAnalytics_CL` | per GB ingested | `enable_traffic_analytics` |
| 4 | Blob storage for the raw logs | per GB-month retained | always on when the module runs |
| — | Two `azurerm_monitor_scheduled_query_rules_alert_v2` rules | per rule-month | `enable_traffic_alerts` |

Meters 1–3 are all per-GB of the *same* flow volume and together dominate the
bill. Meter 4 is a rounding error at any normal retention.

### The formula

Let **`V`** be monthly flow-log volume in GB — the only quantity that matters,
and the one nobody can know before the estate carries traffic.

```
monthly ≈ V × (C + (TA ? P + I : 0))          # meters 1–3, per-GB pipeline
        + V × R × S                            # meter 4, storage at steady state
        + A × N                                # alert rules
```

| Symbol | Meaning |
|---|---|
| `C` | flow-log collection rate, $/GB |
| `P` | Traffic Analytics processing rate, $/GB (higher at the 10-minute interval) |
| `I` | Log Analytics ingestion rate, $/GB |
| `TA` | whether `enable_traffic_analytics` is true |
| `R` | retention in months — `flow_log_retention_days / 30`, so 90 days ≈ 3 |
| `S` | blob storage rate, $/GB-month for the chosen replication tier |
| `A` | scheduled-query alert rule cost, $/rule-month |
| `N` | number of alert rules (2 when `enable_traffic_alerts` is true, else 0) |

To price your own estate, substitute your region's list prices from
<https://prices.azure.com> and your own `V`.

### Rate assumptions — UNVERIFIED, do not quote to a client

> These are **assumptions carried over from decision 0009**, taken as US-region
> list prices and **not verified against `prices.azure.com`** (the authoring
> environment had no egress to it). They are here so the formula above can be
> exercised, not so anyone can rely on the result. Re-verifying them is an open
> follow-up in `TODO.md`.
>
> `C` ≈ **$0.50/GB** · `P` ≈ **$2.00/GB** at the 60-minute interval ·
> `I` ≈ **$2.76/GB** pay-as-you-go analytics ingestion ·
> combined pipeline ≈ **$5.25/GB**, honest band **$4–$6/GB** ·
> `S` ≈ **$0.05/GB-month** Standard hot RA-GZRS plus transactions ·
> `A` ≈ **low single-digit dollars per rule-month** at the module's `PT5M`
> evaluation frequency.

Worked through the formula with those assumed rates, Traffic Analytics on at
60 minutes, and 90-day retention, the spread across plausible volumes is:

| Volume assumption | `V` | Pipeline | Storage | Alerts | Total |
|---|---|---|---|---|---|
| Quiet — freshly provisioned, little real traffic | 2 GB | ≈ $11 | ≈ $0.30 | ≈ $2–5 | **≈ $15/mo** |
| Typical | 25 GB | ≈ $131 | ≈ $4 | ≈ $2–5 | **≈ $140/mo** |
| Busy | 150 GB | ≈ $788 | ≈ $23 | ≈ $2–5 | **≈ $815/mo** |

Every figure in that table is `V` × assumed rates. It is a sensitivity
analysis, not a quote.

### Levers, largest first

- **`enable_traffic_analytics = false`** removes meters 2 and 3 — roughly 90%
  of the bill. It also leaves raw blobs that nothing queries and disables both
  alert rules (they query `AzureNetworkAnalytics_CL`, and the module correctly
  `count`-gates them on the same flag). Cheap and close to worthless.
- **`traffic_analytics_interval` 10 vs 60** is a real multiplier on meter 2
  — *assumption: roughly 2×*. Worth it only for a live SOC consuming the data
  at that latency. Keep 60 unless you have one.
- **NSG scope** is a weak lever: adding an NSG adds its traffic, not a fixed
  fee. The private-endpoint NSG in particular carries a small fraction of
  spoke volume.
- **`flow_log_retention_days`** moves only meter 4, ≈3% of the bill even in
  the Busy row. Shortening it saves nothing meaningful and costs you the
  investigation window.

## Usage

### Basic Configuration

```hcl
module "nsg_flow_logs" {
  source = "./modules/nsg-flow-logs"
  
  location            = "southcentralus"
  region_code         = "scus"
  environment         = "prod"
  resource_group_name = "rg-network-prod-scus"
  
  # Map of NSG names to IDs
  nsg_ids = {
    "nsg-hub-management"  = azurerm_network_security_group.hub_management.id
    "nsg-hub-dmz"         = azurerm_network_security_group.hub_dmz.id
    "nsg-spoke-web"       = azurerm_network_security_group.spoke_web.id
    "nsg-spoke-app"       = azurerm_network_security_group.spoke_app.id
    "nsg-spoke-data"      = azurerm_network_security_group.spoke_data.id
  }
  
  # Log Analytics for Traffic Analytics
  log_analytics_workspace_id          = "1234-5678-..."
  log_analytics_workspace_resource_id = "/subscriptions/.../Microsoft.OperationalInsights/workspaces/law-platform-prod"
  log_analytics_workspace_region      = "southcentralus"
  
  # Enable Traffic Analytics
  enable_traffic_analytics = true
  traffic_analytics_interval = 60  # Process every 60 minutes
  
  # Retention
  flow_log_retention_days = 90
  
  # Private Endpoint
  enable_private_endpoint      = true
  private_endpoint_subnet_id   = azurerm_subnet.management.id
  private_dns_zone_ids         = [azurerm_private_dns_zone.blob.id]
  
  # Alerts
  enable_traffic_alerts   = true
  action_group_ids        = [azurerm_monitor_action_group.security.id]
  high_traffic_threshold_gb = 100
  denied_traffic_threshold  = 1000
  
  tags = local.tags
}
```

### Advanced Configuration (Custom Alerts)

```hcl
module "nsg_flow_logs" {
  source = "./modules/nsg-flow-logs"
  
  # ... basic config ...
  
  # Aggressive security monitoring
  denied_traffic_threshold  = 500  # Lower threshold
  high_traffic_threshold_gb = 50   # Lower threshold
  
  # Faster Traffic Analytics (higher cost)
  traffic_analytics_interval = 10  # Process every 10 minutes
  
  # Longer retention for compliance
  flow_log_retention_days = 365  # 1 year
}
```

## Deployment Steps

### 1. Prerequisites

- ✅ Log Analytics workspace deployed
- ✅ Network Watcher enabled in region (auto-created)
- ✅ NSGs deployed and assigned to subnets
- ✅ Action Groups created for alerts

### 2. Deploy Module

```bash
terraform init
terraform plan -out=flow-logs.tfplan
terraform apply flow-logs.tfplan
```

### 3. Verify Deployment

```bash
# Check flow logs are enabled
az network watcher flow-log list \
  --resource-group NetworkWatcherRG \
  --location southcentralus

# Verify storage account
az storage account show \
  --name stflowlogsscusprod
```

### 4. View Traffic Analytics

1. Navigate to **Azure Portal → Log Analytics workspace**
2. Click **Traffic Analytics** under **Monitoring**
3. Explore **Dashboard**, **Geo Map**, **Top Talkers**

## KQL Queries

### View Top 10 Source IPs by Traffic

```kql
AzureNetworkAnalytics_CL
| where SubType_s == "FlowLog"
| summarize TotalBytes = sum(toint(BytesSent_d) + toint(BytesReceived_d)) by SrcIP_s
| top 10 by TotalBytes desc
| project SourceIP = SrcIP_s, TotalGB = TotalBytes / (1024*1024*1024)
```

### Find All Denied Flows (Security Threats)

```kql
AzureNetworkAnalytics_CL
| where SubType_s == "FlowLog"
| where FlowStatus_s == "D"  // Denied
| project TimeGenerated, SrcIP_s, DestIP_s, DestPort_d, NSGRuleName_s, FlowDirection_s
| order by TimeGenerated desc
```

### Top Denied Destination Ports (Attack Vectors)

```kql
AzureNetworkAnalytics_CL
| where SubType_s == "FlowLog"
| where FlowStatus_s == "D"
| summarize DeniedCount = count() by DestPort = DestPort_d
| top 10 by DeniedCount desc
```

### Outbound Internet Traffic by Destination

```kql
AzureNetworkAnalytics_CL
| where SubType_s == "FlowLog"
| where FlowDirection_s == "O"  // Outbound
| where DestIP_s !startswith "10." and DestIP_s !startswith "172.16." and DestIP_s !startswith "192.168."
| summarize Connections = count() by DestIP_s, DestPort_d
| top 20 by Connections desc
```

### Traffic by NSG and Direction

```kql
AzureNetworkAnalytics_CL
| where SubType_s == "FlowLog"
| summarize FlowCount = count(), TotalBytes = sum(toint(BytesSent_d) + toint(BytesReceived_d)) 
  by NSGName = NSGName_s, Direction = FlowDirection_s
| project NSGName, Direction, FlowCount, TotalGB = TotalBytes / (1024*1024*1024)
```

## Troubleshooting

### Flow Logs Not Appearing

1. **Check Network Watcher is enabled**:
   ```bash
   az network watcher list
   ```
   
2. **Verify NSG Flow Log status**:
   ```bash
   az network watcher flow-log show \
     --name fl-<nsg-name> \
     --resource-group NetworkWatcherRG \
     --location southcentralus
   ```

3. **Check storage account access**:
   - Ensure Network Watcher has write permissions to storage account
   - Verify storage account isn't blocked by firewall rules

### Traffic Analytics Not Showing Data

1. **Allow 10-60 minutes** for initial data processing
2. **Verify workspace region** matches flow log region
3. **Check workspace data ingestion**:
   ```kql
   AzureNetworkAnalytics_CL
   | take 100
   ```

### High Costs

Work the levers in the order the [Cost](#cost) section gives, which is by
size. Summarised:

1. **Increase the TA interval** to 60 minutes if it is at 10 — the largest
   single saving that keeps the data usable.
2. **Turn Traffic Analytics off** (`enable_traffic_analytics = false`) if you
   are not querying it — removes ~90% of the bill, and disables both alerts.
3. **Narrow the NSG list** only if some NSGs carry traffic you genuinely do
   not need logged. Count is not the driver; volume is.
4. **Reduce retention / archive old logs** last. Storage is ≈3% of the bill,
   so this rarely repays the lost investigation window.

## Security Best Practices

✅ **Enable private endpoint** for storage account (no public access)  

> **The endpoint needs a zone, and the zone is not this module's.**
> `enable_private_endpoint` defaults to `true`, but both values it needs
> default to empty, so the module refuses a half-configured endpoint at plan.
> In this repository the `privatelink.blob.core.windows.net` zone is owned by
> `platform-connectivity` behind `deploy_private_dns_zones`, and callers
> derive all three arguments from its exported `blob_private_dns_zone_id` —
> see contract 9 in `docs/CROSS-DOMAIN-CONTRACTS.md`. Do not create a second
> zone of that name in a workload layer.
✅ **Use RAGZRS replication** for compliance and durability  
✅ **Set retention to 90+ days** for incident investigation  
✅ **Enable denied flow alerts** to detect attacks  
✅ **Review denied flows weekly** for security threats  
✅ **Use Traffic Analytics** to identify anomalies  
✅ **Lock storage account** to prevent accidental deletion

## Integration with Sentinel (Optional)

Flow logs can feed into Azure Sentinel for advanced threat detection:

```kql
// Sentinel query: Brute force attack detection
AzureNetworkAnalytics_CL
| where SubType_s == "FlowLog"
| where FlowStatus_s == "D" and DestPort_d in (22, 3389)  // SSH, RDP
| summarize DeniedAttempts = count() by SrcIP_s, DestPort_d, bin(TimeGenerated, 5m)
| where DeniedAttempts > 10  // More than 10 attempts in 5 minutes
| project TimeGenerated, AttackerIP = SrcIP_s, TargetPort = DestPort_d, Attempts = DeniedAttempts
```

## Compliance & Retention

| Compliance Framework | Recommended Retention |
|---|---|
| **SOC 2** | 90 days minimum |
| **ISO 27001** | 90-180 days |
| **HIPAA** | 6 years (2,190 days) |
| **PCI-DSS** | 90 days minimum |
| **GDPR** | As needed, typically 90-180 days |

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `location` | Azure region | `string` | — | yes |
| `region_code` | Short region code (e.g., scus, ncus) | `string` | — | yes |
| `environment` | Environment name (e.g., prod, dev) | `string` | — | yes |
| `resource_group_name` | Resource group name for flow log resources | `string` | — | yes |
| `storage_account_name` | Override for the flow-log storage account name. Null composes `stflowlogs<region_code><environment>`. Required when a second instance shares a region and environment with an existing one. | `string` | `null` | no |
| `nsg_ids` | Map of NSG names to NSG resource IDs to enable flow logs on | `map(string)` | `{}` | no |
| `log_analytics_workspace_id` | Log Analytics workspace ID (short format) | `string` | — | yes |
| `log_analytics_workspace_resource_id` | Log Analytics workspace resource ID (full ARM format) | `string` | — | yes |
| `log_analytics_workspace_region` | Log Analytics workspace region | `string` | — | yes |
| `flow_log_retention_days` | Number of days to retain flow logs in storage | `number` | `90` | no |
| `enable_traffic_analytics` | Enable Traffic Analytics for flow logs | `bool` | `true` | no |
| `traffic_analytics_interval` | Traffic Analytics processing interval in minutes (10 or 60) | `number` | `60` | no |
| `enable_private_endpoint` | Enable private endpoint for flow logs storage account | `bool` | `true` | no |
| `private_endpoint_subnet_id` | Subnet ID for private endpoint. **Required** when `enable_private_endpoint = true` — a `lifecycle.precondition` rejects the plan otherwise. | `string` | `""` | no |
| `private_dns_zone_ids` | Private DNS zone IDs for the blob endpoint. **Required** (at least one) when `enable_private_endpoint = true` — a `lifecycle.precondition` rejects the plan otherwise, because an endpoint with no zone resolves to the public address. | `list(string)` | `[]` | no |
| `allowed_subnet_ids` | Subnet IDs allowed to access flow logs storage account | `list(string)` | `[]` | no |
| `allowed_ip_cidrs` | Public IPv4 CIDR ranges allowed through the flow-logs storage account firewall. Entries that fail to parse are dropped (fail closed). | `list(string)` | `[]` | no |
| `enable_traffic_alerts` | Enable alerts for unusual traffic patterns | `bool` | `true` | no |
| `action_group_ids` | Action Group IDs for traffic alerts | `list(string)` | `[]` | no |
| `high_traffic_threshold_gb` | Threshold in GB for high traffic alert | `number` | `100` | no |
| `denied_traffic_threshold` | Threshold for denied traffic flows to trigger alert | `number` | `1000` | no |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

- `storage_account_id` - Flow logs storage account resource ID
- `storage_account_name` - Storage account name
- `flow_log_ids` - Map of NSG names to flow log IDs
- `traffic_analytics_enabled` - Boolean indicating if TA is enabled
- `flow_log_retention_days` - Retention echoed back from the input
- `traffic_analytics_interval` - Processing interval, or `null` when TA is off
- `private_endpoint_ip` - Blob private endpoint IP, or `null` when disabled

There is **no** `estimated_monthly_cost_usd` output. It existed until
decision 0009 and was deleted rather than repaired: it priced a per-GB meter
by NSG count and shipped a fabricated number into every generated repository.
Use the [Cost](#cost) formula instead.

## References

- [NSG Flow Logs Documentation](https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-nsg-flow-logging-overview)
- [Traffic Analytics Documentation](https://learn.microsoft.com/en-us/azure/network-watcher/traffic-analytics)
- [KQL Reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)

## Phase 2 Task Status

- ✅ **Task 5.2**: NSG Flow Logs + Traffic Analytics  
- **Effort**: 8 hours  
- **Cost**: volume-driven — see [Cost](#cost). No single monthly figure is
  meaningful for this module.  
- **Risk Reduction**: 15% (network visibility)
