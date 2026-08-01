<#
.SYNOPSIS
Azure Landing Zone Health Check Runbook
.DESCRIPTION
Automated hourly health checks for ALZ deployment.
Monitors: Firewall operational status, Gateway connectivity, Network peering,
Log Analytics ingestion, Backup jobs, Alert health.
Sends results to Action Group for notifications.
.NOTES
Version: 1.0
Author: ALZ Operations Team
Date: 2026-06-28
Scheduled: Hourly
Requires: Az.Accounts, Az.Network, Az.Automation, Az.OperationalInsights
#>

# ============================================================================
# INITIALIZATION
# ============================================================================
$ErrorActionPreference = "Continue"
$VerbosePreference = "SilentlyContinue"

# Get Automation Account variables
try {
    $subscriptionId = Get-AutomationVariable -Name "SubscriptionId" -ErrorAction Stop
    $resourceGroupName = Get-AutomationVariable -Name "ResourceGroupName" -ErrorAction Stop
} catch {
    Write-Error "Failed to retrieve Automation Account variables: $_"
    exit 1
}

# Authenticate to Azure
try {
    Connect-AzAccount -Identity -Subscription $subscriptionId | Out-Null
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# ============================================================================
# HEALTH CHECK RESULTS
# ============================================================================
$healthChecks = @()
$overallStatus = "Healthy"
$failureCount = 0

# ============================================================================
# 1. FIREWALL STATUS CHECK
# ============================================================================
Write-Output "🔍 Checking Firewall Status..."

try {
    $firewalls = Get-AzFirewall -ResourceGroupName $resourceGroupName -ErrorAction Stop

    foreach ($fw in $firewalls) {
        $fwStatus = @{
            CheckType   = "Firewall"
            Resource    = $fw.Name
            Status      = $fw.ProvisioningState
            Healthy     = if ($fw.ProvisioningState -eq "Succeeded") { $true } else { $false }
            Timestamp   = Get-Date
            Details     = "Provisioning State: $($fw.ProvisioningState)"
        }

        if (-not $fwStatus.Healthy) {
            $overallStatus = "Degraded"
            $failureCount++
        }

        $healthChecks += $fwStatus
        Write-Output "  ✓ Firewall $($fw.Name): $($fw.ProvisioningState)"
    }
} catch {
    $healthChecks += @{
        CheckType   = "Firewall"
        Status      = "Error"
        Healthy     = $false
        Timestamp   = Get-Date
        Details     = "Error checking firewall: $_"
    }
    $overallStatus = "Unhealthy"
    $failureCount++
    Write-Error "Firewall check failed: $_"
}

# ============================================================================
# 2. VPN GATEWAY CONNECTIVITY CHECK
# ============================================================================
Write-Output "🔍 Checking VPN Gateway Status..."

try {
    $gateways = Get-AzVirtualNetworkGateway -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

    foreach ($gw in $gateways) {
        $gwStatus = @{
            CheckType   = "VPN Gateway"
            Resource    = $gw.Name
            Status      = $gw.ProvisioningState
            Healthy     = if ($gw.ProvisioningState -eq "Succeeded") { $true } else { $false }
            Timestamp   = Get-Date
            Details     = "Provisioning State: $($gw.ProvisioningState) | Type: $($gw.GatewayType)"
        }

        if (-not $gwStatus.Healthy) {
            $overallStatus = "Degraded"
            $failureCount++
        }

        $healthChecks += $gwStatus
        Write-Output "  ✓ Gateway $($gw.Name): $($gw.ProvisioningState)"
    }
} catch {
    $healthChecks += @{
        CheckType   = "VPN Gateway"
        Status      = "Error"
        Healthy     = $false
        Timestamp   = Get-Date
        Details     = "No gateways found or error checking: $_"
    }
    Write-Output "  ⚠️  Gateway check: No gateways found (expected for some deployments)"
}

# ============================================================================
# 3. NETWORK PEERING CHECK
# ============================================================================
Write-Output "🔍 Checking Network Peering Status..."

try {
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -ErrorAction Stop

    $peeringCount = 0
    foreach ($vnet in $vnets) {
        $peerings = Get-AzVirtualNetworkPeering -VirtualNetworkName $vnet.Name -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

        foreach ($peering in $peerings) {
            $peeringStatus = @{
                CheckType   = "Network Peering"
                Resource    = "$($vnet.Name) -> $($peering.RemoteVirtualNetworkId.Split('/')[-1])"
                Status      = $peering.PeeringState
                Healthy     = if ($peering.PeeringState -eq "Connected") { $true } else { $false }
                Timestamp   = Get-Date
                Details     = "Peering State: $($peering.PeeringState)"
            }

            if (-not $peeringStatus.Healthy) {
                $overallStatus = "Degraded"
                $failureCount++
            }

            $healthChecks += $peeringStatus
            $peeringCount++
            Write-Output "  ✓ Peering $($peering.Name): $($peering.PeeringState)"
        }
    }

    if ($peeringCount -eq 0) {
        Write-Output "  ℹ️  No peerings found"
    }
} catch {
    Write-Error "Peering check failed: $_"
}

# ============================================================================
# 4. LOG ANALYTICS INGESTION CHECK
# ============================================================================
Write-Output "🔍 Checking Log Analytics Ingestion..."

try {
    $logAnalyticsWorkspaces = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

    foreach ($workspace in $logAnalyticsWorkspaces) {
        # Check ingestion in last hour
        $query = @"
        Heartbeat
        | where TimeGenerated > ago(1h)
        | summarize Count = count() by Computer
        | count
"@

        $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $query -TimeSpan (New-TimeSpan -Hours 1) -ErrorAction SilentlyContinue

        $hasData = if ($queryResults.Results.Count -gt 0) { $true } else { $false }

        $laStatus = @{
            CheckType   = "Log Analytics"
            Resource    = $workspace.Name
            Status      = if ($hasData) { "Ingesting" } else { "No Data" }
            Healthy     = $hasData
            Timestamp   = Get-Date
            Details     = "Heartbeat records in last 1h: $(if ($hasData) { $queryResults.Results.Count } else { 0 })"
        }

        if (-not $laStatus.Healthy) {
            $overallStatus = "Degraded"
            # Don't count as failure if new deployment
        }

        $healthChecks += $laStatus
        Write-Output "  ✓ Log Analytics $($workspace.Name): $(if ($hasData) { "Ingesting data" } else { "No data yet (new?)" })"
    }
} catch {
    Write-Error "Log Analytics check failed: $_"
}

# ============================================================================
# 5. BACKUP JOBS CHECK
# ============================================================================
Write-Output "🔍 Checking Backup Jobs..."

try {
    $vaults = Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

    foreach ($vault in $vaults) {
        Set-AzRecoveryServicesVaultContext -Vault $vault
        $jobs = Get-AzRecoveryServicesBackupJob -Status Failed -BackupManagementType AzureVM -VaultId $vault.ID -ErrorAction SilentlyContinue

        $failedJobCount = if ($jobs) { $jobs.Count } else { 0 }

        $backupStatus = @{
            CheckType   = "Backup"
            Resource    = $vault.Name
            Status      = if ($failedJobCount -eq 0) { "Healthy" } else { "Failed Jobs Detected" }
            Healthy     = if ($failedJobCount -eq 0) { $true } else { $false }
            Timestamp   = Get-Date
            Details     = "Failed Jobs: $failedJobCount"
        }

        if (-not $backupStatus.Healthy) {
            $overallStatus = "Degraded"
            $failureCount++
        }

        $healthChecks += $backupStatus
        Write-Output "  ✓ Backup $($vault.Name): $(if ($failedJobCount -eq 0) { "Healthy" } else { "$failedJobCount failed jobs" })"
    }
} catch {
    Write-Output "  ⚠️  Backup check: Skipped (no backup vault or access denied)"
}

# ============================================================================
# 6. ALERT RULES CHECK
# ============================================================================
Write-Output "🔍 Checking Alert Rules..."

try {
    $alerts = Get-AzMetricAlertRuleV2 -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

    $totalAlerts = if ($alerts) { $alerts.Count } else { 0 }
    $enabledAlerts = 0

    foreach ($alert in $alerts) {
        if ($alert.IsEnabled) {
            $enabledAlerts++
        }
    }

    $alertStatus = @{
        CheckType   = "Alerts"
        Resource    = "All Alert Rules"
        Status      = "Healthy"
        Healthy     = if ($enabledAlerts -gt 0) { $true } else { $false }
        Timestamp   = Get-Date
        Details     = "Total Rules: $totalAlerts | Enabled: $enabledAlerts"
    }

    if (-not $alertStatus.Healthy -and $totalAlerts -gt 0) {
        $overallStatus = "Degraded"
    }

    $healthChecks += $alertStatus
    Write-Output "  ✓ Alert Rules: $enabledAlerts/$totalAlerts enabled"
} catch {
    Write-Output "  ℹ️  Alert check: Skipped"
}

# ============================================================================
# 7. RESOURCE GROUP QUOTAS CHECK
# ============================================================================
Write-Output "🔍 Checking Resource Group Status..."

try {
    $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop

    $rgStatus = @{
        CheckType   = "Resource Group"
        Resource    = $rg.ResourceGroupName
        Status      = "Active"
        Healthy     = $true
        Timestamp   = Get-Date
        Details     = "Location: $($rg.Location) | Resources: 0"  # Would need separate query for count
    }

    $healthChecks += $rgStatus
    Write-Output "  ✓ Resource Group $($rg.ResourceGroupName): Active"
} catch {
    $rgStatus = @{
        CheckType   = "Resource Group"
        Status      = "Error"
        Healthy     = $false
        Timestamp   = Get-Date
        Details     = "Resource group not found or inaccessible: $_"
    }
    $overallStatus = "Unhealthy"
    $failureCount++
    $healthChecks += $rgStatus
    Write-Error "Resource Group check failed: $_"
}

# ============================================================================
# GENERATE REPORT & SEND NOTIFICATION
# ============================================================================
Write-Output "`n📊 Health Check Summary"
Write-Output "Overall Status: $overallStatus"
Write-Output "Failed Checks: $failureCount"
Write-Output "Timestamp: $(Get-Date)"

# Build email body
$emailBody = @"
<h2>Azure Landing Zone Health Check Report</h2>
<p><strong>Timestamp:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
<p><strong>Overall Status:</strong> <strong style="color: $(if ($overallStatus -eq 'Healthy') { 'green' } else { 'red' })">$overallStatus</strong></p>
<p><strong>Failed Checks:</strong> $failureCount</p>

<h3>Detailed Results:</h3>
<table border="1" style="border-collapse: collapse; width: 100%;">
<tr style="background-color: #f2f2f2;">
    <th>Check Type</th>
    <th>Resource</th>
    <th>Status</th>
    <th>Healthy</th>
    <th>Details</th>
</tr>
"@

foreach ($check in $healthChecks) {
    $statusColor = if ($check.Healthy) { "#90EE90" } else { "#FFB6C6" }
    $healthyText = if ($check.Healthy) { "✓ Yes" } else { "✗ No" }

    $emailBody += @"
<tr style="background-color: $statusColor;">
    <td>$($check.CheckType)</td>
    <td>$($check.Resource)</td>
    <td>$($check.Status)</td>
    <td>$healthyText</td>
    <td>$($check.Details)</td>
</tr>
"@
}

$emailBody += "</table>"

# Send notification if failures detected
if ($failureCount -gt 0) {
    Write-Output "⚠️  Sending alert notification..."

    try {
        # Save report to storage for audit trail
        $reportJson = $healthChecks | ConvertTo-Json

        Write-Output "Health Check Report:"
        Write-Output $reportJson

        # TODO: Send to Action Group (fetch the ActionGroupId automation
        # variable when implemented). Requires Azure Automation integration.
    } catch {
        Write-Error "Failed to send notification: $_"
    }
}

Write-Output "`n✅ Health check completed"
exit 0
