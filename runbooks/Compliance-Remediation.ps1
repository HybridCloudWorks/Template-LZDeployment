<#
.SYNOPSIS
Azure Landing Zone Compliance Remediation Runbook
.DESCRIPTION
Triggered when policy compliance violations detected.
Auto-remediates allowed violations and escalates critical ones.
.NOTES
Version: 1.0
Author: ALZ Operations Team
Date: 2026-06-28
Trigger: Azure Policy compliance event
Requires: Az.Accounts, Az.Policy, Az.ResourceGraph
#>

param(
    [string]$PolicyDefinitionId,
    [string]$ComplianceState = "NonCompliant"
)

$ErrorActionPreference = "Continue"

# Get variables
$subscriptionId = Get-AutomationVariable -Name "SubscriptionId" -ErrorAction Stop
$resourceGroupName = Get-AutomationVariable -Name "ResourceGroupName" -ErrorAction Stop
$orgPrefix = Get-AutomationVariable -Name "OrgPrefix" -ErrorAction Stop

# Authenticate
Connect-AzAccount -Identity -Subscription $subscriptionId | Out-Null

Write-Output "🔍 Compliance Remediation Starting..."
Write-Output "Policy Definition: $PolicyDefinitionId"
Write-Output "Compliance State: $ComplianceState"

$remediationLog = @()

# ============================================================================
# DEFINE REMEDIATABLE VIOLATIONS
# ============================================================================
$remediableViolations = @{
    # Tagging violations
    "tagging-required" = @{
        autoRemediate = $true
        action = "AddMissingTags"
        defaultTags = @{
            "environment"     = "production"
            "managed-by"      = "alz-automation"
            "cost-center"     = "alz"
        }
    }

    # Encryption violations
    "encryption-transit" = @{
        autoRemediate = $true
        action = "EnableEncryption"
    }

    # Storage compliance
    "storage-https-only" = @{
        autoRemediate = $true
        action = "EnableHttpsOnly"
    }

    # Backup requirements
    "backup-enabled" = @{
        autoRemediate = $false  # Requires manual approval
        action = "CreateBackupPolicy"
        severity = "High"
    }
}

# ============================================================================
# GET NON-COMPLIANT RESOURCES
# ============================================================================
Write-Output "`n📊 Querying non-compliant resources..."

try {
    $query = @"
policyresources
| where type == "microsoft.policyinsights/policystates"
| where properties.complianceState == "NonCompliant"
| project resourceId=properties.resourceId, policyAssignmentId=properties.policyAssignmentId
| limit 100
"@

    $nonCompliantResources = Search-AzGraph -Query $query -First 100 -ErrorAction Stop

    Write-Output "Found $($nonCompliantResources.Count) non-compliant resources"

    foreach ($resource in $nonCompliantResources) {
        $resourceId = $resource.resourceId
        $resourceName = $resourceId.Split('/')[-1]
        $resourceType = $resourceId.Split('/')[8]

        Write-Output "  - $resourceName ($resourceType)"

        # ============================================================================
        # APPLY REMEDIATION BASED ON VIOLATION TYPE
        # ============================================================================

        # Example 1: Missing tags remediation
        if ($resourceType -match "storageAccounts|virtualMachines|databases") {
            try {
                # Get resource
                $resource = Get-AzResource -ResourceId $resourceId -ErrorAction SilentlyContinue

                if ($resource) {
                    # Apply default tags
                    $tags = $resource.Tags
                    if (-not $tags) { $tags = @{} }

                    $defaultTags = @{
                        "environment"     = "production"
                        "managed-by"      = "alz-automation"
                        "cost-center"     = "alz"
                    }

                    $updated = $false
                    foreach ($tagKey in $defaultTags.Keys) {
                        if (-not $tags.ContainsKey($tagKey)) {
                            $tags[$tagKey] = $defaultTags[$tagKey]
                            $updated = $true
                        }
                    }

                    if ($updated) {
                        Update-AzTag -ResourceId $resourceId -Tag $tags -Operation Replace | Out-Null

                        $remediationLog += @{
                            timestamp      = Get-Date
                            resourceId     = $resourceId
                            resourceName   = $resourceName
                            action         = "AddMissingTags"
                            status         = "Success"
                            tagsAdded      = $defaultTags.Count
                        }

                        Write-Output "    ✅ Tags remediated: $resourceName"
                    }
                }
            } catch {
                $remediationLog += @{
                    timestamp      = Get-Date
                    resourceId     = $resourceId
                    resourceName   = $resourceName
                    action         = "AddMissingTags"
                    status         = "Failed"
                    error          = $_
                }

                Write-Error "Failed to remediate tags for ${resourceName}: $_"
            }
        }

        # Example 2: Storage HTTPS-only remediation
        if ($resourceType -eq "storageAccounts") {
            try {
                $storageAccount = Get-AzStorageAccount -ResourceId $resourceId -ErrorAction SilentlyContinue

                if ($storageAccount -and -not $storageAccount.EnableHttpsTrafficOnly) {
                    Set-AzStorageAccount -ResourceGroupName $storageAccount.ResourceGroupName `
                        -Name $storageAccount.StorageAccountName -EnableHttpsTrafficOnly $true | Out-Null

                    $remediationLog += @{
                        timestamp      = Get-Date
                        resourceId     = $resourceId
                        resourceName   = $resourceName
                        action         = "EnableHttpsOnly"
                        status         = "Success"
                    }

                    Write-Output "    ✅ HTTPS enabled: $resourceName"
                }
            } catch {
                Write-Error "Failed to enable HTTPS for ${resourceName}: $_"
            }
        }

        # Example 3: VM encryption remediation
        if ($resourceType -eq "virtualMachines") {
            Write-Output "    ℹ️  VM encryption requires manual review (escalating)"

            $remediationLog += @{
                timestamp      = Get-Date
                resourceId     = $resourceId
                resourceName   = $resourceName
                action         = "EnableEncryption"
                status         = "Escalated"
                severity       = "High"
                reason         = "Requires manual verification and approval"
            }
        }
    }

} catch {
    Write-Error "Error querying non-compliant resources: $_"
}

# ============================================================================
# GENERATE REMEDIATION REPORT
# ============================================================================
Write-Output "`n" + "="*60
Write-Output "📋 REMEDIATION REPORT"
Write-Output "="*60

$successCount = @($remediationLog | Where-Object { $_.status -eq "Success" }).Count
$escalatedCount = @($remediationLog | Where-Object { $_.status -eq "Escalated" }).Count
$failedCount = @($remediationLog | Where-Object { $_.status -eq "Failed" }).Count

Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output ""
Write-Output "Results:"
Write-Output "  ✅ Auto-Remediated: $successCount"
Write-Output "  ⚠️  Escalated for Review: $escalatedCount"
Write-Output "  ❌ Failed: $failedCount"
Write-Output ""

foreach ($log in $remediationLog) {
    $symbol = switch ($log.status) {
        "Success"    { "✅" }
        "Escalated"  { "⚠️" }
        "Failed"     { "❌" }
    }

    Write-Output "$symbol $($log.resourceName)"
    Write-Output "   Action: $($log.action) | Status: $($log.status)"

    if ($log.error) {
        Write-Output "   Error: $($log.error)"
    }
}

Write-Output ""
Write-Output "="*60

# Export report
$report = @{
    timestamp           = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    subscriptionId      = $subscriptionId
    complianceState     = $ComplianceState
    remediationCount    = @{
        successful = $successCount
        escalated  = $escalatedCount
        failed     = $failedCount
        total      = $remediationLog.Count
    }
    remediationLog      = $remediationLog
}

$report | ConvertTo-Json -Depth 5 | Out-File -FilePath "./alz-remediation-report-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').json"

Write-Output "`n✅ Compliance remediation completed"

if ($escalatedCount -gt 0) {
    Write-Output "⚠️  $escalatedCount items require manual review"
}

exit 0
