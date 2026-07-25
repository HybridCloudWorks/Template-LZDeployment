# Microsoft Defender for Cloud Baseline Module

## ⚠️ OPTIONAL DEPLOYMENT - NOT ENABLED BY DEFAULT

**Cost Impact**: $1,500 - $3,000/month recurring  
**Security Benefit**: Comprehensive threat protection across all Azure resources  
**Phase 1 Task**: 5.5 - Enable Microsoft Defender for Cloud

---

## Overview

This Terraform module enables Microsoft Defender for Cloud across multiple Azure subscriptions with comprehensive threat protection plans.

**Defender Plans Included**:
- ✅ Virtual Machines (P2 with vulnerability assessment)
- ✅ App Services
- ✅ Storage Accounts (V2 with malware scanning)
- ✅ SQL Servers & SQL VMs
- ✅ Containers (AKS, ACR)
- ✅ Key Vaults
- ✅ Azure Resource Manager
- ✅ DNS

---

## Why Optional?

1. **Cost Consideration**: $1,500-$3,000/month is significant for early-stage deployments
2. **Production Timing**: More valuable once you have production workloads deployed
3. **Free Tier Available**: Azure provides free basic Defender (no advanced threat protection)
4. **Incremental Adoption**: Can enable specific plans (e.g., just VMs) rather than all at once

---

## When to Enable

**Enable Defender when you**:
- Have production workloads running
- Store sensitive customer data
- Need compliance certifications (SOC 2, ISO 27001, HIPAA)
- Want vulnerability assessments and threat detection
- Need security score and recommendations
- Require 24/7 threat monitoring

**Wait to enable if**:
- Still in development/testing phase
- No production data yet
- Budget constraints
- Planning proof-of-concept only

---

## How to Deploy

### Prerequisites

1. **Log Analytics Workspace**: Deploy management platform first
   ```bash
   cd terraform/live/platform-management
   terraform apply
   ```

2. **Subscription IDs**: Gather all subscription IDs to protect
   ```bash
   az account list --query "[].{Name:name, ID:id}" --output table
   ```

3. **Security Contact Email**: Decide who receives security alerts

### Step 1: Create `defender.tfvars`

Create a new file in `terraform/live/global/defender.tfvars`:

```hcl
# Enable Defender for Cloud across all subscriptions

subscriptions = {
  connectivity = {
    id   = "00000000-0000-0000-0000-000000000000"  # Replace with actual ID
    name = "Platform-Connectivity"
    tier = "Standard"  # or "Free" for basic protection
  }
  management = {
    id   = "00000000-0000-0000-0000-000000000001"
    name = "Platform-Management"
    tier = "Standard"
  }
  workload_prod = {
    id   = "00000000-0000-0000-0000-000000000002"
    name = "Workload-Production"
    tier = "Standard"
  }
  workload_nonprod = {
    id   = "00000000-0000-0000-0000-000000000003"
    name = "Workload-NonProduction"
    tier = "Standard"
  }
  sandbox = {
    id   = "00000000-0000-0000-0000-000000000004"
    name = "Sandbox"
    tier = "Free"  # Keep sandbox on Free tier
  }
}

security_contact_email = "security@yourcompany.com"
security_contact_phone = "+1-555-123-4567"  # Optional

# Defender plans (all enabled by default)
enable_defender_for_servers         = true
enable_defender_for_app_services    = true
enable_defender_for_storage         = true
enable_defender_for_sql             = true
enable_defender_for_containers      = true
enable_defender_for_key_vault       = true
enable_defender_for_resource_manager = true
enable_defender_for_dns             = true

# Log Analytics workspace (from platform-management deployment)
log_analytics_workspace_id = "/subscriptions/<MGMT_SUB_ID>/resourceGroups/rg-logging-mgmt-scus-prod-01/providers/Microsoft.OperationalInsights/workspaces/log-analytics-prod-01"
```

### Step 2: Add Module to Global Layer

Edit `terraform/live/global/main.tf` and add:

```hcl
module "defender_baseline" {
  source = "../../modules/defender-baseline"
  
  subscriptions                   = var.defender_subscriptions
  security_contact_email          = var.defender_security_contact_email
  security_contact_phone          = var.defender_security_contact_phone
  enable_defender_for_servers     = var.enable_defender_for_servers
  enable_defender_for_app_services = var.enable_defender_for_app_services
  enable_defender_for_storage     = var.enable_defender_for_storage
  enable_defender_for_sql         = var.enable_defender_for_sql
  enable_defender_for_containers  = var.enable_defender_for_containers
  enable_defender_for_key_vault   = var.enable_defender_for_key_vault
  enable_defender_for_resource_manager = var.enable_defender_for_resource_manager
  enable_defender_for_dns         = var.enable_defender_for_dns
  log_analytics_workspace_id      = var.defender_log_analytics_workspace_id
  default_tags                    = var.default_tags
}
```

### Step 3: Add Variables to Global Layer

Edit `terraform/live/global/variables.tf`:

```hcl
variable "defender_subscriptions" {
  description = "Subscriptions to enable Defender on"
  type = map(object({
    id   = string
    name = string
    tier = string
  }))
  default = {}
}

variable "defender_security_contact_email" {
  description = "Email for security alerts"
  type        = string
  default     = ""
}

variable "defender_security_contact_phone" {
  description = "Phone for security contact"
  type        = string
  default     = ""
}

variable "enable_defender_for_servers" {
  description = "Enable Defender for Servers"
  type        = bool
  default     = false  # Disabled by default
}

# ... repeat for all other enable_defender_for_* variables
```

### Step 4: Deploy

```bash
cd terraform/live/global
terraform init
terraform plan -var-file=defender.tfvars
terraform apply -var-file=defender.tfvars
```

### Step 5: Verify in Azure Portal

1. Navigate to **Microsoft Defender for Cloud**
2. Check **Environment settings** → Select subscriptions
3. Verify **Defender plans** shows "On" for enabled plans
4. Review **Security Score** (takes 24 hours to populate)
5. Check **Recommendations** for actionable items

---

## Cost Optimization Tips

### Start Small

Enable only critical plans first:
```hcl
enable_defender_for_servers      = true   # Most important
enable_defender_for_storage      = true   # If storing sensitive data
enable_defender_for_sql          = true   # If using SQL databases
enable_defender_for_containers   = false  # Wait until AKS deployed
enable_defender_for_app_services = false  # Wait until apps deployed
enable_defender_for_key_vault    = false  # Lower priority
enable_defender_for_resource_manager = false
enable_defender_for_dns          = false
```

**Cost Impact**: ~$50-$100/month for just VMs, storage, and SQL

### Free Tier for Non-Production

Set non-production subscriptions to `tier = "Free"`:
```hcl
workload_nonprod = {
  id   = "..."
  name = "Workload-NonProduction"
  tier = "Free"  # No cost, basic protection only
}
```

### Monitor Costs

```bash
# Check Defender costs
az consumption usage list \
  --start-date 2026-05-01 \
  --end-date 2026-05-31 \
  --query "[?contains(instanceName, 'Defender')].{Name:instanceName, Cost:pretaxCost}" \
  --output table
```

---

## Validation

After deployment, run:

```bash
# Check Defender status across subscriptions
for sub_id in $(az account list --query "[].id" -o tsv); do
  echo "Subscription: $sub_id"
  az security pricing list --subscription $sub_id --query "[].{Name:name, Tier:pricingTier}" -o table
  echo ""
done

# Check security contact
az security contact list --output table

# Check auto-provisioning
az security auto-provisioning-setting list --output table
```

---

## Disable Defender (if needed)

To disable and stop costs:

```bash
# Set all plans to Free tier
terraform apply -var-file=defender.tfvars \
  -var='enable_defender_for_servers=false' \
  -var='enable_defender_for_app_services=false' \
  # ... etc

# Or destroy the module entirely
terraform destroy -target=module.defender_baseline
```

---

## Security Best Practices

1. **Review Recommendations Weekly**: Portal → Defender → Recommendations
2. **Configure Workflow Automation**: Auto-remediate common issues
3. **Enable Just-In-Time VM Access**: Reduce attack surface
4. **Set Up Alert Rules**: Integrate with security SIEM
5. **Monthly Security Review**: Check security score trends

---

## Additional Resources

- [Microsoft Defender for Cloud Pricing](https://azure.microsoft.com/pricing/details/defender-for-cloud/)
- [Enable Defender Plans](https://learn.microsoft.com/azure/defender-for-cloud/enable-enhanced-security)
- [Defender for Servers](https://learn.microsoft.com/azure/defender-for-cloud/defender-for-servers-introduction)
- [Security Alerts](https://learn.microsoft.com/azure/defender-for-cloud/alerts-overview)
- [Security Score](https://learn.microsoft.com/azure/defender-for-cloud/secure-score-security-controls)

---

**Module Version**: 1.0  
**Last Updated**: May 28, 2026  
**Status**: Ready for optional deployment  
**Phase 1 Task**: 5.5 (OPTIONAL - DEFERRED)
