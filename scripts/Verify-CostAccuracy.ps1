<#
.SYNOPSIS
Azure Landing Zone Cost Verification & Accuracy Auditing Script
.DESCRIPTION
Pulls actual costs from Azure Cost Management API, compares against estimated costs,
calculates variance, and identifies cost overruns per component.
.PARAMETER SubscriptionId
Azure subscription ID
.PARAMETER EstimatedMonthlyCost
Estimated monthly cost from form (for comparison)
.PARAMETER Month
Month to analyze (format: YYYY-MM, default: current month)
.PARAMETER ReportPath
Output path for cost report (default: ./alz-cost-report.json)
.EXAMPLE
.\Verify-CostAccuracy.ps1 -SubscriptionId "xxxx" -EstimatedMonthlyCost 5000 -Month "2026-06"
.NOTES
Version: 1.0
Author: ALZ Operations Team
Date: 2026-06-28
Requires: Az.CostManagement, Az.Accounts
Target Accuracy: ±5% variance
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [decimal]$EstimatedMonthlyCost,

    [Parameter(Mandatory=$false)]
    [string]$Month = (Get-Date -Format "yyyy-MM"),

    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "./alz-cost-report.json"
)

# Import config
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "Get-AlzConfig.ps1")

class CostComponent {
    [string]$Name
    [decimal]$EstimatedCost
    [decimal]$ActualCost
    [decimal]$Variance
    [decimal]$VariancePercent
    [string]$Status  # Within Budget, Overrun, Underrun
}

$report = @{
    timestamp           = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    subscriptionId      = $SubscriptionId
    month               = $Month
    costAccuracyTarget  = "±5%"
    components          = @()
    summary             = @{}
}

Write-Host "📊 Azure Cost Verification & Analysis Report" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId | Month: $Month" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# ============================================================================
# FETCH ACTUAL COSTS FROM AZURE COST MANAGEMENT API
# ============================================================================
Write-Host "`n🔍 Fetching actual costs from Azure Cost Management..." -ForegroundColor Yellow

try {
    # Set date range
    $startDate = "$Month-01"
    $endDate = [datetime]::ParseExact("$Month-01", "yyyy-MM-dd", $null).AddMonths(1).AddDays(-1).ToString("yyyy-MM-dd")

    # Call Cost Management API
    $costData = az costmanagement query --subscription $SubscriptionId --timeframe Custom `
        --from "$($startDate)T00:00:00Z" --to "$($endDate)T23:59:59Z" `
        --dataset-granularity daily `
        --dataset-grouping type=Dimension name=ServiceName `
        --output json 2>&1 | ConvertFrom-Json -ErrorAction Stop

    # ============================================================================
    # PARSE AND CATEGORIZE COSTS
    # ============================================================================
    Write-Host "✅ Cost data retrieved. Processing..." -ForegroundColor Green

    $costByService = @{}
    $totalActualCost = 0

    if ($costData.properties.rows) {
        foreach ($row in $costData.properties.rows) {
            # Format: [date, service, cost, currency]
            $serviceName = $row[0]
            $costAmount = [decimal]$row[1]

            if (-not $costByService.ContainsKey($serviceName)) {
                $costByService[$serviceName] = 0
            }
            $costByService[$serviceName] += $costAmount
            $totalActualCost += $costAmount
        }
    } else {
        Write-Host "⚠️  No cost data found for period. Check subscription and date range." -ForegroundColor Yellow
        $totalActualCost = 0
    }

    # ============================================================================
    # MAP AZURE SERVICES TO ALZ COMPONENTS
    # ============================================================================
    Write-Host "📍 Mapping Azure services to ALZ components..." -ForegroundColor Yellow

    $componentMapping = @{
        "Virtual Networks" = "hub-network"
        "Firewall"         = "hub-network"
        "VPN Gateway"      = "hub-network"
        "Log Analytics"    = "management-baseline"
        "Application Insights" = "management-baseline"
        "Automation Account" = "management-baseline"
        "Backup Service"   = "backup-baseline"
        "Microsoft Defender for Cloud" = "defender-baseline"
        "Network Watcher"  = "hub-network"
    }

    $componentCosts = @{}
    foreach ($component in ([ALZConfig]::Modules.Keys)) {
        $componentCosts[$component] = 0
    }

    # Aggregate costs by component
    foreach ($service in $costByService.Keys) {
        $matched = $false
        foreach ($azService in $componentMapping.Keys) {
            if ($service -like "*$azService*" -or $azService -like "*$service*") {
                $component = $componentMapping[$azService]
                $componentCosts[$component] += $costByService[$service]
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $componentCosts["other"] += $costByService[$service]
        }
    }

    # ============================================================================
    # COMPARE WITH ESTIMATED COSTS
    # ============================================================================
    Write-Host "`n📊 Cost Comparison Analysis:" -ForegroundColor Cyan

    # Estimate breakdown (simplified for demo)
    $estimatedByComponent = @{
        "firewall"          = 0.25 * $EstimatedMonthlyCost
        "log-analytics"     = 0.10 * $EstimatedMonthlyCost
        "networks"          = 0.15 * $EstimatedMonthlyCost
        "compute"           = 0.30 * $EstimatedMonthlyCost
        "backup"            = 0.10 * $EstimatedMonthlyCost
        "other"             = 0.10 * $EstimatedMonthlyCost
    }

    foreach ($component in $componentCosts.Keys) {
        if ($componentCosts[$component] -gt 0) {
            $actual = $componentCosts[$component]
            $estimated = if ($estimatedByComponent.ContainsKey($component)) {
                $estimatedByComponent[$component]
            } else {
                $EstimatedMonthlyCost * 0.05  # Default 5% allocation
            }

            $variance = $actual - $estimated
            $variancePercent = if ($estimated -gt 0) {
                ($variance / $estimated) * 100
            } else {
                0
            }

            # Determine status
            $status = if ($variancePercent -le -5) {
                "Underrun"
            } elseif ($variancePercent -ge 5) {
                "Overrun"
            } else {
                "Within Budget"
            }

            $componentCost = [CostComponent]@{
                Name            = $component
                EstimatedCost   = [Math]::Round($estimated, 2)
                ActualCost      = [Math]::Round($actual, 2)
                Variance        = [Math]::Round($variance, 2)
                VariancePercent = [Math]::Round($variancePercent, 2)
                Status          = $status
            }

            $report.components += $componentCost

            # Display result
            $symbol = switch ($status) {
                "Within Budget" { "✅" }
                "Underrun"      { "💰" }
                "Overrun"       { "⚠️" }
            }
            Write-Host "  $symbol $component"
            Write-Host "     Estimated: \$$estimated | Actual: \$$actual"
            Write-Host "     Variance: \$$variance ($($variancePercent)%)"
        }
    }

    # ============================================================================
    # CALCULATE SUMMARY
    # ============================================================================
    $totalVariance = $totalActualCost - $EstimatedMonthlyCost
    $totalVariancePercent = if ($EstimatedMonthlyCost -gt 0) {
        ($totalVariance / $EstimatedMonthlyCost) * 100
    } else {
        0
    }

    $overallStatus = if ($totalVariancePercent -le -5) {
        "Underrun"
    } elseif ($totalVariancePercent -ge 5) {
        "Overrun"
    } else {
        "Within Target (±5%)"
    }

    $report.summary = @{
        estimatedMonthlyCost = [Math]::Round($EstimatedMonthlyCost, 2)
        actualMonthlyCost    = [Math]::Round($totalActualCost, 2)
        totalVariance        = [Math]::Round($totalVariance, 2)
        variancePercent      = [Math]::Round($totalVariancePercent, 2)
        accuracyStatus       = $overallStatus
        accuracyGrade        = if ($totalVariancePercent -le 5 -and $totalVariancePercent -ge -5) {
            "A+ (Excellent)"
        } elseif ($totalVariancePercent -le 10 -and $totalVariancePercent -ge -10) {
            "A (Good)"
        } else {
            "B- (Review Needed)"
        }
    }

    # ============================================================================
    # DISPLAY SUMMARY
    # ============================================================================
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "💰 COST VERIFICATION SUMMARY" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Cyan

    Write-Host "`nEstimated Monthly Cost: \$$($EstimatedMonthlyCost)"
    Write-Host "Actual Monthly Cost:    \$$([Math]::Round($totalActualCost, 2))"
    Write-Host "Total Variance:         \$$([Math]::Round($totalVariance, 2)) ($($totalVariancePercent)%)"
    Write-Host ""
    Write-Host "Overall Status: $overallStatus"
    Write-Host "Accuracy Grade: $($report.summary.accuracyGrade)"
    Write-Host ""

    if ($totalVariancePercent -ge 5) {
        Write-Host "⚠️  COST OVERRUN DETECTED - Review resource utilization" -ForegroundColor Yellow
    } elseif ($totalVariancePercent -le -5) {
        Write-Host "💰 COST UNDERRUN - Consider reallocating resources or scaling up" -ForegroundColor Yellow
    } else {
        Write-Host "✅ COST ESTIMATION ACCURATE - Within ±5% target" -ForegroundColor Green
    }

    Write-Host "`n" + "="*60 -ForegroundColor Cyan

    # ============================================================================
    # RECOMMENDATIONS
    # ============================================================================
    Write-Host "`n💡 OPTIMIZATION RECOMMENDATIONS:" -ForegroundColor Cyan

    $recommendations = @()

    if ($componentCosts["firewall"] -gt $EstimatedMonthlyCost * 0.3) {
        $recommendations += "⚠️  Firewall costs are high - Consider reserved instances or standard tier for non-critical regions"
    }

    if ($componentCosts["compute"] -gt $EstimatedMonthlyCost * 0.4) {
        $recommendations += "⚠️  Compute costs are elevated - Review VM sizing and consider spot instances"
    }

    if ($componentCosts["backup"] -gt $EstimatedMonthlyCost * 0.15) {
        $recommendations += "💾 Backup costs exceeding budget - Review retention policies"
    }

    if ($recommendations.Count -eq 0) {
        $recommendations += "✅ No optimization opportunities identified"
    }

    foreach ($rec in $recommendations) {
        Write-Host "  $rec"
    }

    # ============================================================================
    # EXPORT REPORT
    # ============================================================================
    Write-Host "`n📄 Generating detailed report..." -ForegroundColor Yellow

    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Host "✅ Report saved to: $ReportPath" -ForegroundColor Green

    # Return exit code based on accuracy
    if ($totalVariancePercent -le 10 -and $totalVariancePercent -ge -10) {
        Write-Host "`n✅ COST VERIFICATION PASSED" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n⚠️  COST VERIFICATION - REVIEW REQUIRED" -ForegroundColor Yellow
        exit 1
    }

} catch {
    Write-Host "❌ Error during cost verification: $_" -ForegroundColor Red
    Write-Host "Ensure you have:" -ForegroundColor Yellow
    Write-Host "  - Azure CLI installed and authenticated"
    Write-Host "  - Cost Management API access enabled"
    Write-Host "  - Proper subscription permissions"
    exit 2
}
