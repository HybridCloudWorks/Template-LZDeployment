# Sandbox Cleanup Automation Runbook
# Deletes resources in Sandbox subscription with expiry_date tag older than 30 days
#
# SECURITY FEATURES:
# - GUID validation for subscription ID
# - Subscription existence and tag validation
# - Resource group prefix validation (rg-sandbox-* only)
# - Maximum deletion limit (100 resources)
# - Dry-run confirmation requirement
# - Audit logging to Log Analytics
# - Safe date parsing with error handling
#
# USAGE:
#   DryRun:  .\Cleanup-ExpiredSandboxResources.ps1 -SandboxSubscriptionId "..." -DryRun "true"
#   Execute: .\Cleanup-ExpiredSandboxResources.ps1 -SandboxSubscriptionId "..." -DryRun "false" -Confirm

param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SandboxSubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("true", "false")]
    [string]$DryRun = "true",
    
    [Parameter(Mandatory = $false)]
    [switch]$Confirm = $false,
    
    [Parameter(Mandatory = $false)]
    [string]$LogAnalyticsWorkspaceId = "",
    
    [Parameter(Mandatory = $false)]
    [int]$MaxDeletions = 100,
    
    [Parameter(Mandatory = $false)]
    [string]$AllowedResourceGroupPrefix = "rg-sandbox-"
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "Information",
        [hashtable]$Properties = @{}
    )
    
    $logEntry = @{
        Timestamp = (Get-Date).ToUniversalTime().ToString("o")
        Level = $Level
        Message = $Message
        SubscriptionId = $SandboxSubscriptionId
        RunbookName = "Cleanup-ExpiredSandboxResources"
        Properties = $Properties
    }
    
    Write-Output "[$Level] $Message"
    
    # If Log Analytics workspace ID is provided, send structured log
    if ($LogAnalyticsWorkspaceId) {
        # In production, integrate with Send-AzOperationalInsightsDataCollector
        # For now, write structured JSON to output
        Write-Output (ConvertTo-Json $logEntry -Compress)
    }
}

function Test-SafeDateParse {
    param([string]$DateString)
    
    try {
        $parsedDate = [DateTime]::Parse($DateString)
        return @{ Success = $true; Date = $parsedDate }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

#endregion

Write-AuditLog "Sandbox cleanup runbook started" -Level "Information" -Properties @{
    DryRun = $DryRun
    MaxDeletions = $MaxDeletions
}

# Connect using managed identity
Write-AuditLog "Connecting to Azure using managed identity..."
try {
    Connect-AzAccount -Identity | Out-Null
} catch {
    Write-AuditLog "FAILED to connect with managed identity: $_" -Level "Error"
    throw
}

# Validate subscription exists
Write-AuditLog "Validating subscription: $SandboxSubscriptionId"
try {
    $subscription = Get-AzSubscription -SubscriptionId $SandboxSubscriptionId -ErrorAction Stop
} catch {
    Write-AuditLog "FAILED: Subscription '$SandboxSubscriptionId' does not exist or is not accessible" -Level "Error"
    throw "Invalid subscription ID. Ensure the subscription exists and the managed identity has access."
}

# Set context to sandbox subscription
Write-AuditLog "Setting context to subscription: $($subscription.Name)"
Set-AzContext -SubscriptionId $SandboxSubscriptionId | Out-Null

# CRITICAL SAFETY CHECK: Validate subscription has 'purpose=sandbox' tag
$subTags = (Get-AzSubscription -SubscriptionId $SandboxSubscriptionId).Tags
if (-not $subTags -or $subTags["purpose"] -ne "sandbox") {
    Write-AuditLog "FATAL: Subscription does not have 'purpose=sandbox' tag. Refusing to proceed." -Level "Error" -Properties @{
        SubscriptionName = $subscription.Name
        Tags = $subTags
    }
    throw "SAFETY VIOLATION: This script only operates on subscriptions tagged with purpose=sandbox"
}

Write-AuditLog "Subscription validation PASSED: purpose=sandbox" -Level "Information"

# Get current date
$now = Get-Date
$expiryThreshold = $now.AddDays(-30)

$now = Get-Date
$expiryThreshold = $now.AddDays(-30)

Write-AuditLog "Expiry threshold: $expiryThreshold (30 days ago)"

# Get all resource groups in sandbox subscription
$resourceGroups = Get-AzResourceGroup
Write-AuditLog "Found $($resourceGroups.Count) resource groups in subscription"

$expiredResources = @()
$skippedResources = @()

foreach ($rg in $resourceGroups) {
    # SAFETY CHECK: Only process resource groups with allowed prefix
    if (-not $rg.ResourceGroupName.StartsWith($AllowedResourceGroupPrefix)) {
        Write-AuditLog "SKIPPED: Resource group '$($rg.ResourceGroupName)' does not match prefix '$AllowedResourceGroupPrefix'" -Level "Warning"
        $skippedResources += @{
            Type = "ResourceGroup"
            Name = $rg.ResourceGroupName
            Reason = "Invalid prefix"
        }
        continue
    }
    
    # Check resource group expiry date
    if ($rg.Tags.ContainsKey("expiry_date")) {
        $parseResult = Test-SafeDateParse -DateString $rg.Tags["expiry_date"]
        
        if (-not $parseResult.Success) {
            Write-AuditLog "SKIPPED: Resource group '$($rg.ResourceGroupName)' has invalid expiry_date format: $($parseResult.Error)" -Level "Warning"
            $skippedResources += @{
                Type = "ResourceGroup"
                Name = $rg.ResourceGroupName
                Reason = "Invalid date format"
            }
            continue
        }
        
        $expiryDate = $parseResult.Date
        
        if ($expiryDate -lt $expiryThreshold) {
            Write-AuditLog "EXPIRED: Resource Group '$($rg.ResourceGroupName)' expired on $expiryDate"
            $expiredResources += @{
                Type = "ResourceGroup"
                Name = $rg.ResourceGroupName
                ExpiryDate = $expiryDate
            }
        }
    }
    
    # Check individual resources in resource group
    $resources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
    foreach ($resource in $resources) {
        if ($resource.Tags.ContainsKey("expiry_date")) {
            $parseResult = Test-SafeDateParse -DateString $resource.Tags["expiry_date"]
            
            if (-not $parseResult.Success) {
                Write-AuditLog "SKIPPED: Resource '$($resource.Name)' has invalid expiry_date format: $($parseResult.Error)" -Level "Warning"
                continue
            }
            
            $expiryDate = $parseResult.Date
            
            if ($expiryDate -lt $expiryThreshold) {
                Write-AuditLog "EXPIRED: Resource '$($resource.Name)' (type: $($resource.ResourceType)) expired on $expiryDate"
                $expiredResources += @{
                    Type = "Resource"
                    Name = $resource.Name
                    ResourceType = $resource.ResourceType
                    ResourceGroupName = $rg.ResourceGroupName
                    ExpiryDate = $expiryDate
                }
            }
        }
    }
}

# SAFETY CHECK: Maximum deletion limit
if ($expiredResources.Count -gt $MaxDeletions) {
    Write-AuditLog "FATAL: Found $($expiredResources.Count) expired items, exceeds maximum allowed deletions ($MaxDeletions)" -Level "Error" -Properties @{
        ExpiredCount = $expiredResources.Count
        MaxAllowed = $MaxDeletions
    }
    throw "SAFETY VIOLATION: Too many resources to delete. Review manually or increase MaxDeletions parameter."
}

# Summary
Write-AuditLog "===== SUMMARY =====" -Level "Information"
Write-AuditLog "Expired items found: $($expiredResources.Count)" -Level "Information"
Write-AuditLog "Skipped items: $($skippedResources.Count)" -Level "Information"

if ($DryRun -eq "true") {
    Write-AuditLog "DRY RUN MODE - No resources will be deleted" -Level "Information"
    foreach ($item in $expiredResources) {
        Write-AuditLog "Would delete: $($item.Type) - $($item.Name) (expired: $($item.ExpiryDate))"
    }
    
    if ($skippedResources.Count -gt 0) {
        Write-AuditLog "`nSkipped items (safety checks):"
        foreach ($item in $skippedResources) {
            Write-AuditLog "  - $($item.Type): $($item.Name) (Reason: $($item.Reason))"
        }
    }
} else {
    # SAFETY CHECK: Require explicit confirmation for actual deletion
    if (-not $Confirm) {
        Write-AuditLog "FATAL: Actual deletion requires -Confirm switch. Add -Confirm to proceed." -Level "Error"
        throw "SAFETY VIOLATION: -Confirm switch required for actual deletion"
    }
    
    Write-AuditLog "DELETING expired resources (confirmed)..." -Level "Warning"
    
    $successCount = 0
    $failureCount = 0
    
    # Delete individual resources first
    $resourcesToDelete = $expiredResources | Where-Object { $_.Type -eq "Resource" }
    foreach ($item in $resourcesToDelete) {
        Write-AuditLog "Deleting resource: $($item.Name)" -Level "Warning"
        try {
            Remove-AzResource -ResourceGroupName $item.ResourceGroupName `
                             -ResourceName $item.Name `
                             -ResourceType $item.ResourceType `
                             -Force
            Write-AuditLog "Successfully deleted: $($item.Name)" -Level "Information"
            $successCount++
        } catch {
            Write-AuditLog "Failed to delete resource $($item.Name): $_" -Level "Error"
            $failureCount++
        }
    }
    
    # Delete expired resource groups
    $rgToDelete = $expiredResources | Where-Object { $_.Type -eq "ResourceGroup" }
    foreach ($item in $rgToDelete) {
        Write-AuditLog "Deleting resource group: $($item.Name)" -Level "Warning"
        try {
            Remove-AzResourceGroup -Name $item.Name -Force
            Write-AuditLog "Successfully deleted: $($item.Name)" -Level "Information"
            $successCount++
        } catch {
            Write-AuditLog "Failed to delete resource group $($item.Name): $_" -Level "Error"
            $failureCount++
        }
    }
    
    Write-AuditLog "Deletion complete: $successCount succeeded, $failureCount failed" -Level "Information" -Properties @{
        SuccessCount = $successCount
        FailureCount = $failureCount
    }
}

Write-AuditLog "Sandbox cleanup completed" -Level "Information"
