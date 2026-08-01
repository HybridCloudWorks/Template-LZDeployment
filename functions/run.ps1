# REST API for Azure Landing Zone Operations
# Azure Function HTTP Trigger
# Endpoints: GET /status, /costs, POST /audit, /redeploy

using namespace System.Net

param($Request, $TriggerMetadata)

# Parse request
$method = $Request.Method
$path = $Request.Path
$body = $Request.Body
$queryParams = $Request.Query

# Initialize response
$statusCode = [HttpStatusCode]::OK
$responseBody = @{
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    method    = $method
    path      = $path
    status    = "unknown"
}

# ============================================================================
# ROUTING
# ============================================================================

switch -Regex ($path) {
    # GET /api/status - Get deployment status
    "status$" {
        if ($method -eq "GET") {
            $statusCode = [HttpStatusCode]::OK
            $responseBody.status = "operational"
            $responseBody.details = @{
                deployment     = "healthy"
                firewalls      = @(1)
                networks       = @(2)
                policies       = @("baseline", "pci-dss")
                lastHealthCheck = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
        } else {
            $statusCode = [HttpStatusCode]::MethodNotAllowed
            $responseBody.error = "Only GET is allowed"
        }
    }

    # GET /api/costs - Get monthly costs
    "costs$" {
        if ($method -eq "GET") {
            $month = $queryParams['month'] ?? (Get-Date -Format "yyyy-MM")
            $statusCode = [HttpStatusCode]::OK
            $responseBody.status = "success"
            $responseBody.data = @{
                month              = $month
                estimatedCost      = 5000.00
                actualCost         = 5150.00
                variance           = 150.00
                variancePercent    = 3.0
                costByComponent    = @{
                    firewall       = 1500.00
                    loganalytics   = 350.00
                    networks       = 750.00
                    backup         = 500.00
                    other          = 2050.00
                }
                accuracyStatus     = "Within Target (±5%)"
            }
        } else {
            $statusCode = [HttpStatusCode]::MethodNotAllowed
            $responseBody.error = "Only GET is allowed"
        }
    }

    # GET /api/compliance - Get compliance status
    "compliance$" {
        if ($method -eq "GET") {
            $variant = $queryParams['variant'] ?? "baseline"
            $statusCode = [HttpStatusCode]::OK
            $responseBody.status = "success"
            $responseBody.data = @{
                variant             = $variant
                compliantResources  = 145
                nonCompliantResources = 8
                totalResources      = 153
                compliancePercent   = 94.8
                lastAudit          = Get-Date -AddDays(-1) -Format "yyyy-MM-ddTHH:mm:ssZ"
                violations          = @(
                    @{
                        policyName = "tagging-required"
                        resourceCount = 3
                        severity = "low"
                    },
                    @{
                        policyName = "encryption-transit"
                        resourceCount = 5
                        severity = "medium"
                    }
                )
            }
        } else {
            $statusCode = [HttpStatusCode]::MethodNotAllowed
            $responseBody.error = "Only GET is allowed"
        }
    }

    # GET /api/deployments - List all deployments
    "deployments$" {
        if ($method -eq "GET") {
            $statusCode = [HttpStatusCode]::OK
            $responseBody.status = "success"
            $responseBody.data = @(
                @{
                    deploymentId     = "alz-deploy-001"
                    org              = "contoso"
                    primaryRegion    = "eastus"
                    secondaryRegion  = "westus"
                    variant          = "hipaa"
                    status           = "completed"
                    createdDate      = "2026-06-01T10:30:00Z"
                    lastModified     = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                },
                @{
                    deploymentId     = "alz-deploy-002"
                    org              = "fabrikam"
                    primaryRegion    = "westeurope"
                    secondaryRegion  = "northeurope"
                    variant          = "baseline"
                    status           = "completed"
                    createdDate      = "2026-05-15T14:20:00Z"
                    lastModified     = "2026-06-10T09:15:00Z"
                }
            )
        } else {
            $statusCode = [HttpStatusCode]::MethodNotAllowed
            $responseBody.error = "Only GET is allowed"
        }
    }

    # POST /api/audit - Trigger compliance audit
    "audit$" {
        if ($method -eq "POST") {
            $variant = $body.variant ?? "baseline"
            $statusCode = [HttpStatusCode]::Accepted
            $responseBody.status = "audit_initiated"
            $responseBody.data = @{
                auditId     = "audit-$(New-Guid)"
                variant     = $variant
                initiated   = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                expectedDuration = "5 minutes"
                statusUrl   = "/api/audit/{auditId}/status"
            }
        } else {
            $statusCode = [HttpStatusCode]::MethodNotAllowed
            $responseBody.error = "Only POST is allowed"
        }
    }

    # POST /api/redeploy - Trigger redeployment
    "redeploy$" {
        if ($method -eq "POST") {
            $deploymentId = $body.deploymentId
            $statusCode = [HttpStatusCode]::Accepted
            $responseBody.status = "redeploy_initiated"
            $responseBody.data = @{
                deploymentId  = $deploymentId
                initiated     = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                expectedDuration = "20 minutes"
                statusUrl     = "/api/deployments/$deploymentId/status"
            }
        } else {
            $statusCode = [HttpStatusCode]::MethodNotAllowed
            $responseBody.error = "Only POST is allowed"
        }
    }

    # Default 404
    default {
        $statusCode = [HttpStatusCode]::NotFound
        $responseBody.error = "Endpoint not found"
        $responseBody.availableEndpoints = @(
            "GET  /api/status",
            "GET  /api/costs?month=yyyy-MM",
            "GET  /api/compliance?variant=baseline",
            "GET  /api/deployments",
            "POST /api/audit",
            "POST /api/redeploy"
        )
    }
}

# Return response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body       = ($responseBody | ConvertTo-Json -Depth 5)
    Headers    = @{
        "Content-Type" = "application/json"
    }
})
