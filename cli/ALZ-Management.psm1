<#
.SYNOPSIS
Azure Landing Zone Customer Management CLI Module
.DESCRIPTION
PowerShell module for operations team to manage ALZ deployments.
Functions: Get-ALZDeployments, Get-ALZCost, Get-ALZCompliance, etc.
.NOTES
Version: 1.0
Author: ALZ Operations Team
Date: 2026-06-28
#>

# ============================================================================
# INITIALIZATION
# ============================================================================
$script:ALZConfig = @{
    ApiEndpoint = "https://alz-api.azurewebsites.net"
    ApiVersion  = "1.0"
}

# ============================================================================
# FUNCTION: Get-ALZDeployments
# ============================================================================
function Get-ALZDeployments {
    <#
    .SYNOPSIS
    List all ALZ deployments
    .PARAMETER Organization
    Filter by organization name
    .PARAMETER Status
    Filter by deployment status
    .EXAMPLE
    Get-ALZDeployments -Organization "contoso"
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$Organization,

        [Parameter(Mandatory=$false)]
        [ValidateSet("completed", "in-progress", "failed")]
        [string]$Status
    )

    try {
        $uri = "$($script:ALZConfig.ApiEndpoint)/api/deployments"
        $deployments = Invoke-RestMethod -Uri $uri -Method GET

        if ($Organization) {
            $deployments = $deployments | Where-Object { $_.org -like "*$Organization*" }
        }

        if ($Status) {
            $deployments = $deployments | Where-Object { $_.status -eq $Status }
        }

        return $deployments
    } catch {
        Write-Error "Failed to retrieve deployments: $_"
    }
}

# ============================================================================
# FUNCTION: Get-ALZCost
# ============================================================================
function Get-ALZCost {
    <#
    .SYNOPSIS
    Get cost information for a deployment
    .PARAMETER DeploymentId
    Deployment ID
    .PARAMETER Month
    Month in format YYYY-MM (default: current month)
    .EXAMPLE
    Get-ALZCost -DeploymentId "alz-deploy-001" -Month "2026-06"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DeploymentId,

        [Parameter(Mandatory=$false)]
        [string]$Month = (Get-Date -Format "yyyy-MM")
    )

    try {
        $uri = "$($script:ALZConfig.ApiEndpoint)/api/costs?month=$Month"
        $costData = Invoke-RestMethod -Uri $uri -Method GET

        Write-Host "💰 Cost Report: $DeploymentId - $Month" -ForegroundColor Cyan
        Write-Host "  Estimated: `$$($costData.data.estimatedCost)"
        Write-Host "  Actual: `$$($costData.data.actualCost)"
        Write-Host "  Variance: `$$($costData.data.variance) ($($costData.data.variancePercent)%)"
        Write-Host ""
        Write-Host "  Cost Breakdown:"
        foreach ($component in $costData.data.costByComponent.PSObject.Properties) {
            Write-Host "    - $($component.Name): `$$($component.Value)"
        }

        return $costData.data
    } catch {
        Write-Error "Failed to retrieve cost data: $_"
    }
}

# ============================================================================
# FUNCTION: Get-ALZCompliance
# ============================================================================
function Get-ALZCompliance {
    <#
    .SYNOPSIS
    Get compliance status for a deployment
    .PARAMETER DeploymentId
    Deployment ID
    .PARAMETER Variant
    Compliance variant (baseline, pci-dss, hipaa, fedramp)
    .EXAMPLE
    Get-ALZCompliance -DeploymentId "alz-deploy-001" -Variant "hipaa"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DeploymentId,

        [Parameter(Mandatory=$false)]
        [ValidateSet("baseline", "pci-dss", "hipaa", "fedramp")]
        [string]$Variant = "baseline"
    )

    try {
        $uri = "$($script:ALZConfig.ApiEndpoint)/api/compliance?variant=$Variant"
        $complianceData = Invoke-RestMethod -Uri $uri -Method GET

        Write-Host "🔐 Compliance Report: $DeploymentId - $Variant" -ForegroundColor Cyan
        Write-Host "  Compliance Rate: $($complianceData.data.compliancePercent)%"
        Write-Host "  Compliant Resources: $($complianceData.data.compliantResources)"
        Write-Host "  Non-Compliant Resources: $($complianceData.data.nonCompliantResources)"
        Write-Host ""
        Write-Host "  Violations:"
        foreach ($violation in $complianceData.data.violations) {
            Write-Host "    - $($violation.policyName): $($violation.resourceCount) resources [$($violation.severity)]"
        }

        return $complianceData.data
    } catch {
        Write-Error "Failed to retrieve compliance data: $_"
    }
}

# ============================================================================
# FUNCTION: Get-ALZStatus
# ============================================================================
function Get-ALZStatus {
    <#
    .SYNOPSIS
    Get operational status of ALZ
    .EXAMPLE
    Get-ALZStatus
    #>
    param()

    try {
        $uri = "$($script:ALZConfig.ApiEndpoint)/api/status"
        $statusData = Invoke-RestMethod -Uri $uri -Method GET

        Write-Host "🏥 Azure Landing Zone Status" -ForegroundColor Cyan
        Write-Host "  Overall Status: $($statusData.details.deployment)"
        Write-Host "  Firewalls: $($statusData.details.firewalls.Count)"
        Write-Host "  Networks: $($statusData.details.networks.Count)"
        Write-Host "  Compliance Variants: $(($statusData.details.policies -join ', '))"
        Write-Host "  Last Health Check: $($statusData.details.lastHealthCheck)"

        return $statusData.details
    } catch {
        Write-Error "Failed to retrieve status: $_"
    }
}

# ============================================================================
# FUNCTION: Trigger-ALZAudit
# ============================================================================
function Trigger-ALZAudit {
    <#
    .SYNOPSIS
    Trigger compliance audit
    .PARAMETER Variant
    Compliance variant to audit
    .EXAMPLE
    Trigger-ALZAudit -Variant "hipaa"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("baseline", "pci-dss", "hipaa", "fedramp")]
        [string]$Variant
    )

    try {
        $uri = "$($script:ALZConfig.ApiEndpoint)/api/audit"
        $body = @{
            variant = $Variant
        } | ConvertTo-Json

        $auditData = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType "application/json"

        Write-Host "✅ Audit initiated: $($auditData.data.auditId)" -ForegroundColor Green
        Write-Host "   Variant: $Variant"
        Write-Host "   Expected Duration: $($auditData.data.expectedDuration)"
        Write-Host "   Status URL: $($auditData.data.statusUrl)"

        return $auditData.data
    } catch {
        Write-Error "Failed to trigger audit: $_"
    }
}

# ============================================================================
# FUNCTION: Invoke-ALZRedeployment
# ============================================================================
function Invoke-ALZRedeployment {
    <#
    .SYNOPSIS
    Trigger redeployment of ALZ
    .PARAMETER DeploymentId
    Deployment ID to redeploy
    .EXAMPLE
    Invoke-ALZRedeployment -DeploymentId "alz-deploy-001"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DeploymentId
    )

    $confirm = Read-Host "Are you sure you want to redeploy $DeploymentId? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Redeployment cancelled"
        return
    }

    try {
        $uri = "$($script:ALZConfig.ApiEndpoint)/api/redeploy"
        $body = @{
            deploymentId = $DeploymentId
        } | ConvertTo-Json

        $redeployData = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType "application/json"

        Write-Host "✅ Redeployment initiated" -ForegroundColor Green
        Write-Host "   Deployment ID: $DeploymentId"
        Write-Host "   Expected Duration: $($redeployData.data.expectedDuration)"
        Write-Host "   Status URL: $($redeployData.data.statusUrl)"

        return $redeployData.data
    } catch {
        Write-Error "Failed to initiate redeployment: $_"
    }
}

# ============================================================================
# FUNCTION: Export-ALZCostReport
# ============================================================================
function Export-ALZCostReport {
    <#
    .SYNOPSIS
    Export cost report for all deployments
    .PARAMETER OutputPath
    Output file path (default: ./alz-cost-report.csv)
    .PARAMETER Month
    Month to report (default: current month)
    .EXAMPLE
    Export-ALZCostReport -OutputPath "./reports/costs.csv"
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$OutputPath = "./alz-cost-report-$(Get-Date -Format 'yyyy-MM-dd').csv",

        [Parameter(Mandatory=$false)]
        [string]$Month = (Get-Date -Format "yyyy-MM")
    )

    try {
        $deployments = Get-ALZDeployments

        $reportData = @()
        foreach ($deployment in $deployments) {
            $costData = Get-ALZCost -DeploymentId $deployment.deploymentId -Month $Month

            $reportData += [PSCustomObject]@{
                DeploymentId       = $deployment.deploymentId
                Organization       = $deployment.org
                PrimaryRegion      = $deployment.primaryRegion
                Variant            = $deployment.variant
                EstimatedCost      = $costData.estimatedCost
                ActualCost         = $costData.actualCost
                Variance           = $costData.variance
                VariancePercent    = $costData.variancePercent
                Month              = $Month
                ExportDate         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }

        $reportData | Export-Csv -Path $OutputPath -NoTypeInformation
        Write-Host "✅ Cost report exported to: $OutputPath" -ForegroundColor Green
        Write-Host "   Records: $($reportData.Count)"

    } catch {
        Write-Error "Failed to export cost report: $_"
    }
}

# ============================================================================
# EXPORT MODULE MEMBERS
# ============================================================================
Export-ModuleMember -Function @(
    "Get-ALZDeployments",
    "Get-ALZCost",
    "Get-ALZCompliance",
    "Get-ALZStatus",
    "Trigger-ALZAudit",
    "Invoke-ALZRedeployment",
    "Export-ALZCostReport"
)
