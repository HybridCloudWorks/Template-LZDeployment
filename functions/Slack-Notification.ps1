# Azure Function: Slack Notifications for ALZ Events
# HTTP Trigger
# Sends deployment, compliance, cost, and incident alerts to Slack

using namespace System.Net

param($Request, $TriggerMetadata)

# ============================================================================
# CONFIGURATION
# ============================================================================
$slackWebhookUrl = $env:SLACK_WEBHOOK_URL  # Set as Function App setting
$colorMap = @{
    "success"     = "#36a64f"
    "warning"     = "#ff9900"
    "error"       = "#ff0000"
    "info"        = "#0099ff"
}

$statusCode = [HttpStatusCode]::OK
$responseBody = @{
    status  = "message_sent"
    timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
}

# ============================================================================
# PARSE REQUEST
# ============================================================================
try {
    $eventData = $Request.Body | ConvertFrom-Json -ErrorAction Stop
} catch {
    $statusCode = [HttpStatusCode]::BadRequest
    $responseBody.error = "Invalid JSON in request body"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $statusCode
        Body       = ($responseBody | ConvertTo-Json)
    })
    exit
}

# ============================================================================
# BUILD SLACK MESSAGE
# ============================================================================
$eventType = $eventData.eventType
$severity  = $eventData.severity ?? "info"
$color     = $colorMap[$severity] ?? $colorMap["info"]

$slackMessage = @{
    text = $eventType
    attachments = @(
        @{
            color      = $color
            title      = $eventData.title ?? $eventType
            text       = $eventData.description
            fields     = @()
            ts         = [int][double]::Parse((Get-Date -UFormat %s))
        }
    )
}

# ============================================================================
# EVENT-SPECIFIC FORMATTING
# ============================================================================
switch ($eventType) {
    # Deployment Events
    "deployment_started" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Organization"
                value = $eventData.organization
                short = $true
            },
            @{
                title = "Regions"
                value = "$($eventData.primaryRegion) → $($eventData.secondaryRegion)"
                short = $true
            },
            @{
                title = "Compliance Variant"
                value = $eventData.variant
                short = $true
            },
            @{
                title = "Expected Duration"
                value = "20 minutes"
                short = $true
            }
        )
    }

    "deployment_completed" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Organization"
                value = $eventData.organization
                short = $true
            },
            @{
                title = "Status"
                value = "✅ Successful"
                short = $true
            },
            @{
                title = "Duration"
                value = $eventData.duration
                short = $true
            },
            @{
                title = "Resources Created"
                value = $eventData.resourceCount
                short = $true
            }
        )
    }

    "deployment_failed" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Organization"
                value = $eventData.organization
                short = $true
            },
            @{
                title = "Status"
                value = "❌ Failed"
                short = $true
            },
            @{
                title = "Error"
                value = $eventData.errorMessage
                short = $false
            },
            @{
                title = "Action Required"
                value = "Review logs and contact support"
                short = $false
            }
        )
    }

    # Compliance Events
    "compliance_violation_detected" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Policy"
                value = $eventData.policyName
                short = $true
            },
            @{
                title = "Severity"
                value = $eventData.severity
                short = $true
            },
            @{
                title = "Resources Affected"
                value = $eventData.resourceCount
                short = $true
            },
            @{
                title = "Remediation Status"
                value = $eventData.remediationStatus ?? "Pending"
                short = $true
            }
        )
    }

    "compliance_audit_completed" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Variant"
                value = $eventData.variant
                short = $true
            },
            @{
                title = "Compliance Rate"
                value = "$($eventData.compliancePercent)%"
                short = $true
            },
            @{
                title = "Compliant Resources"
                value = $eventData.compliantCount
                short = $true
            },
            @{
                title = "Non-Compliant Resources"
                value = $eventData.nonCompliantCount
                short = $true
            }
        )
    }

    # Cost Events
    "cost_overrun_detected" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Organization"
                value = $eventData.organization
                short = $true
            },
            @{
                title = "Overrun Amount"
                value = "`$$($eventData.overrunAmount)"
                short = $true
            },
            @{
                title = "Variance"
                value = "$($eventData.variancePercent)%"
                short = $true
            },
            @{
                title = "Recommendation"
                value = $eventData.recommendation ?? "Review cost drivers"
                short = $false
            }
        )
    }

    "cost_optimization_opportunity" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Opportunity"
                value = $eventData.opportunityType
                short = $true
            },
            @{
                title = "Potential Savings"
                value = "`$$($eventData.monthlySavings)"
                short = $true
            },
            @{
                title = "Annual Savings"
                value = "`$$($eventData.annualSavings)"
                short = $true
            },
            @{
                title = "Action"
                value = $eventData.recommendedAction ?? "Review in dashboard"
                short = $false
            }
        )
    }

    # Incident Events
    "firewall_incident" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Resource"
                value = $eventData.resourceName
                short = $true
            },
            @{
                title = "Status"
                value = $eventData.status
                short = $true
            },
            @{
                title = "Incident Details"
                value = $eventData.details
                short = $false
            },
            @{
                title = "Required Action"
                value = $eventData.action ?? "Investigate immediately"
                short = $false
            }
        )
    }

    "backup_job_failed" {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Vault"
                value = $eventData.vaultName
                short = $true
            },
            @{
                title = "Resource"
                value = $eventData.resourceName
                short = $true
            },
            @{
                title = "Error"
                value = $eventData.errorMessage
                short = $false
            },
            @{
                title = "Retry"
                value = "Automatically retrying in 1 hour"
                short = $true
            }
        )
    }

    default {
        $slackMessage.attachments[0].fields = @(
            @{
                title = "Event Type"
                value = $eventType
                short = $true
            },
            @{
                title = "Severity"
                value = $severity.ToUpper()
                short = $true
            }
        )
    }
}

# Add footer with timestamp
$slackMessage.attachments[0].footer = "Azure Landing Zone | ALZ Automation"
$slackMessage.attachments[0].footer_icon = "https://raw.githubusercontent.com/Azure/azure-sdk-for-python/main/doc/sphinx/_static/logo.png"

# ============================================================================
# SEND TO SLACK
# ============================================================================
try {
    $jsonPayload = $slackMessage | ConvertTo-Json -Depth 5

    $params = @{
        Uri         = $slackWebhookUrl
        Method      = "POST"
        Body        = $jsonPayload
        ContentType = "application/json"
    }

    Invoke-RestMethod @params | Out-Null

    $responseBody.slackStatus = "Message sent successfully"
    $statusCode = [HttpStatusCode]::OK

} catch {
    $responseBody.error = "Failed to send Slack message: $_"
    $statusCode = [HttpStatusCode]::InternalServerError
    Write-Error $_
}

# ============================================================================
# RETURN RESPONSE
# ============================================================================
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body       = ($responseBody | ConvertTo-Json)
    Headers    = @{
        "Content-Type" = "application/json"
    }
})
