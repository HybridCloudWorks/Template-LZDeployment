# Azure Sentinel SIEM Module - OPTIONAL

## ⚠️ Status: Module Scaffold - Implementation TBD

This module is **not deployed by default** due to significant cost and requirement for a dedicated Security Operations Center (SOC) team. Enable it when you have security analysts ready to monitor and respond to alerts.

## Overview

This module provisions **Azure Sentinel** (Microsoft's cloud-native SIEM) for security event correlation, threat detection, and automated incident response across your Azure Landing Zone.

## What You Get

✅ **Security Information & Event Management (SIEM)** - Centralized log analysis  
✅ **Threat Intelligence** - Integrated Microsoft Threat Intelligence feed  
✅ **ML-Based Anomaly Detection** - User/entity behavior analytics (UEBA)  
✅ **Automated Playbooks** - Logic Apps for incident response  
✅ **SOC Dashboard** - Security operations visualization  
✅ **Incident Management** - Case tracking and workflow  
✅ **Compliance Reporting** - SOC 2, ISO 27001, PCI-DSS dashboards

## Cost Estimate

| Component | Typical Monthly Cost |
|---|---|
| **Sentinel Ingestion** (~5GB/day) | ~$200 |
| **Log Analytics** (data retention) | ~$75 |
| **Logic Apps** (playbooks, ~1000 runs) | ~$25 |
| **Total** | **~$300/month** |

**Cost scales with:**
- Number of data sources (VMs, NSGs, firewalls, apps)
- Log volume per day
- Data retention period (default 90 days)
- Playbook execution frequency

## When to Enable

**Enable Sentinel if:**
- ✅ Have dedicated security analysts (SOC team)
- ✅ Need to correlate security events across infrastructure
- ✅ Compliance requires SIEM capabilities (SOC 2, ISO 27001)
- ✅ Want automated threat hunting
- ✅ Need incident response workflows
- ✅ Managing 50+ Azure resources

**Do NOT enable if:**
- ❌ No SOC team to monitor/respond to alerts
- ❌ Azure Activity Logs + basic monitoring is sufficient
- ❌ Budget constraints are tight
- ❌ Fewer than 50 resources (use Azure Monitor instead)

## What's Already Monitored (Without Sentinel)

Azure provides **basic security monitoring** without Sentinel:
- ✅ Azure Activity Logs - API calls, changes
- ✅ Azure Monitor - Metrics, alerts
- ✅ NSG Flow Logs - Network traffic (Phase 2)
- ✅ Azure Firewall logs - Threat intel hits (Phase 2)
- ✅ Defender for Cloud (optional) - Resource security posture

**Sentinel adds correlation, ML, and automation** - not just logging!

## Features This Module Will Provide

### 1. Data Connectors
Pre-configured connectors for:
- **Azure Activity Logs** - All management plane operations
- **NSG Flow Logs** - Network traffic analysis
- **Azure Firewall** - Threat intelligence hits
- **Azure AD Sign-Ins** - Identity-based attacks
- **Security Center** - Security recommendations
- **Key Vault** - Secret access audit
- **Custom connectors** - Third-party sources via API

### 2. Analytics Rules
Built-in detection rules:
- **Brute force attacks** - Multiple failed logins
- **Impossible travel** - Sign-ins from impossible locations
- **Suspicious IP** - Known malicious IP connections
- **Privilege escalation** - Unusual role assignments
- **Data exfiltration** - Large data transfers
- **Malware detected** - Defender for Endpoint alerts
- **Custom rules** - KQL-based detections

### 3. Automated Playbooks (Logic Apps)
Pre-built incident response workflows:
- **Email security team** - High-severity incident notification
- **Block malicious IP** - Auto-add to NSG deny rule
- **Isolate VM** - Quarantine compromised virtual machine
- **Revoke user session** - Disable compromised Azure AD account
- **Create ticket** - ServiceNow/Jira integration
- **Enrich incident** - Add threat intelligence context

### 4. Workbooks & Dashboards
Security operation dashboards:
- **Security posture overview** - Compliance score
- **Incident timeline** - Recent security events
- **Threat intelligence** - Active threats targeting you
- **User behavior** - Anomalous activity detection
- **Network topology** - Attack surface visualization
- **Compliance dashboard** - SOC 2, ISO 27001 evidence

## Deployment Steps (When Ready)

### 1. Prerequisites

- [ ] **SOC team ready** - Analysts trained on Sentinel
- [ ] **Budget approved** - $300/month minimum (scales with logs)
- [ ] **Log Analytics workspace** - Already deployed (Platform Management)
- [ ] **Data sources deployed** - NSG Flow Logs, Firewall, Activity Logs
- [ ] **Playbook approvals** - Security team confirms response actions

### 2. Enable in Configuration

Copy `.azure/deployment-options.yaml.example` to `.azure/deployment-options.yaml` (if you haven't already) and edit it:
```yaml
modules:
  sentinel:
    enabled: true  # Change from false
    data_retention_days: 90
    enable_ueba: true  # User behavior analytics
    enable_playbooks: true  # Automated response
```

Or run the interactive script:
```powershell
.\scripts\Configure-DeploymentOptions.ps1
```

### 3. Deploy Module

```bash
terraform init
terraform plan -target=module.sentinel_siem -out=sentinel.tfplan
terraform apply sentinel.tfplan
```

### 4. Onboard Data Sources

After deployment:
1. Enable data connectors (Activity Logs, NSG, Firewall)
2. Configure analytics rules (enable built-in detections)
3. Test playbooks (verify Logic Apps execute correctly)
4. Create SOC dashboards (customize workbooks)
5. Train SOC team (incident response procedures)

## Typical Data Sources & Volume

| Data Source | Log Volume/Day | Monthly Cost |
|---|---|---|
| **Azure Activity Logs** | ~500 MB | $30 |
| **NSG Flow Logs** (10 NSGs) | ~2 GB | $120 |
| **Azure Firewall** | ~1 GB | $60 |
| **Azure AD Sign-Ins** | ~500 MB | $30 |
| **Key Vault Audits** | ~100 MB | $6 |
| **Security Center** | ~200 MB | $12 |
| **VM Logs** (optional, 10 VMs) | ~1 GB | $60 |
| **Total (without VMs)** | **~4.3 GB** | **~$258** |

**Cost scales linearly with log volume.**

## Common Use Cases

### 1. Brute Force Attack Detection
**Scenario**: Attacker tries multiple passwords against Azure AD accounts

**Sentinel detects**:
```kql
SigninLogs
| where ResultType != 0  // Failed sign-ins
| summarize FailedAttempts = count() by UserPrincipalName, IPAddress, bin(TimeGenerated, 5m)
| where FailedAttempts > 10
```

**Automated response**: Playbook blocks IP in NSG, notifies security team

### 2. Impossible Travel Detection
**Scenario**: User signs in from New York, then London 2 hours later (impossible)

**Sentinel detects**: Built-in UEBA analytics rule

**Automated response**: Playbook revokes user session, requires MFA re-authentication

### 3. Data Exfiltration Detection
**Scenario**: 100 GB uploaded to external storage in 1 hour (anomalous)

**Sentinel detects**:
```kql
AzureNetworkAnalytics_CL
| where FlowDirection_s == "O"  // Outbound
| summarize TotalBytes = sum(BytesSent_d) by SrcIP_s, bin(TimeGenerated, 1h)
| where TotalBytes > 100000000000  // > 100 GB
```

**Automated response**: Playbook isolates VM, creates high-severity incident

## Compliance Mapping

| Framework | Sentinel Benefit |
|---|---|
| **SOC 2** | SIEM required for Type 2 compliance |
| **ISO 27001** | Log monitoring and correlation (Control A.12.4.1) |
| **PCI-DSS** | Requirement 10.6 - Log review and analysis |
| **HIPAA** | Security incident detection (§164.308(a)(6)(ii)) |
| **NIST CSF** | Detect (DE) and Respond (RS) functions |
| **GDPR** | Breach detection within 72 hours |

**Sentinel provides audit evidence for compliance reports.**

## Integration with Phase 2 Modules

Sentinel leverages **Phase 2 core implementations**:

✅ **NSG Flow Logs** → Sentinel analyzes network traffic patterns  
✅ **Azure Firewall Threat Intel** → Sentinel correlates threat hits  
✅ **TLS 1.2 Policy** → Sentinel alerts on policy violations  

**Phase 2 core provides data sources; Sentinel provides intelligence.**

## Trade-offs

### Pros
✅ Centralized security event correlation  
✅ ML-based anomaly detection  
✅ Automated incident response  
✅ Compliance audit evidence  
✅ Reduced MTTR (mean time to respond)  
✅ Microsoft threat intelligence integration

### Cons
❌ Significant cost ($300+/month, scales with logs)  
❌ Requires SOC team to monitor/respond  
❌ Initial tuning required (reduce false positives)  
❌ Complexity - steep learning curve  
❌ Value increases over time (needs baseline)

## Alternative: Azure Monitor + Basic Alerts

**Already available** without Sentinel:
- ✅ Azure Activity Log alerts
- ✅ Azure Monitor metric alerts
- ✅ NSG Flow Log queries (Phase 2)
- ✅ Basic security recommendations

**Use this until:**
- You have a SOC team
- Managing 50+ resources
- Compliance explicitly requires SIEM

## Implementation Timeline

**Phase 2 Optional** (On-demand):
- Effort: 12 hours (setup + tuning)
- Cost: $300/month minimum (scales with data)
- Risk reduction: +10% (threat detection coverage)
- SOC training: +40 hours

**Recommended approach**:
1. Deploy Phase 2 core (NSG Flow Logs, Firewall Threat Intel)
2. Collect logs for 30 days (baseline)
3. Hire/train SOC analysts
4. Enable Sentinel when team is ready
5. Tune analytics rules (reduce false positives)

## KQL Query Examples

### Find All Failed Sign-Ins by User
```kql
SigninLogs
| where TimeGenerated > ago(24h)
| where ResultType != 0
| summarize FailedLogins = count() by UserPrincipalName, IPAddress
| order by FailedLogins desc
```

### Detect Unusual Resource Deletions
```kql
AzureActivity
| where TimeGenerated > ago(7d)
| where OperationNameValue endswith "DELETE"
| where ActivityStatusValue == "Success"
| summarize Deletions = count() by Caller, ResourceGroup
| where Deletions > 5  // More than 5 deletions is unusual
```

### Find High-Risk Sign-Ins
```kql
SigninLogs
| where TimeGenerated > ago(24h)
| where RiskLevelDuringSignIn == "high" or RiskLevelAggregated == "high"
| project TimeGenerated, UserPrincipalName, IPAddress, Location, RiskDetail
```

## Next Steps

1. ✅ **Assess SOC readiness** - Do you have security analysts?
2. ✅ **Budget approval** - $300/month minimum (estimate based on log volume)
3. ✅ **Deploy Phase 2 core first** - NSG Flow Logs provide data for Sentinel
4. ⏳ **Module implementation** - TBD when SOC team is ready
5. ⏳ **Data connector configuration** - Enable Azure Activity, NSG, Firewall
6. ⏳ **Playbook customization** - Tailor automated responses
7. ⏳ **SOC training** - 40-hour Sentinel certification course

## References

- [Azure Sentinel Documentation](https://learn.microsoft.com/en-us/azure/sentinel/)
- [Sentinel Pricing Calculator](https://azure.microsoft.com/en-us/pricing/details/microsoft-sentinel/)
- [KQL Quick Reference](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [Sentinel Playbook Templates](https://github.com/Azure/Azure-Sentinel/tree/master/Playbooks)

## Phase 2 Task Status

- ⚠️ **Task 9.2**: Azure Sentinel SIEM - **OPTIONAL MODULE**  
- **Status**: Scaffold created, implementation deferred  
- **Effort**: 12 hours deployment + 40 hours SOC training  
- **Cost**: $300/month minimum (scales with log volume)  
- **Decision**: Enable when SOC team is ready

---

**💡 To enable this module**: Run `.\scripts\Configure-DeploymentOptions.ps1` and set `sentinel.enabled = true`
