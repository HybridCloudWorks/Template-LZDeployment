#Requires -Version 7.0
<#
.SYNOPSIS
    Phase 2 remediation: adds the missing `pull_request` federated identity
    credential to the READ-ONLY plan service principal's app registration.

.DESCRIPTION
    Every PR-triggered workflow currently fails Azure login with:

        AADSTS700213: No matching federated identity record found for
        presented assertion subject 'repo:<owner>/<repo>:pull_request'

    because the plan SP app registration (the identity behind the
    AZURE_PLAN_CLIENT_ID repository secret) has no federated credential for
    the `pull_request` OIDC subject. This script builds and (with -Apply)
    executes the exact remediation:

        az ad app federated-credential create --id <APP_ID> --parameters '{
          "name":     "<CredentialName>",
          "issuer":   "https://token.actions.githubusercontent.com",
          "subject":  "repo:<owner>/<repo>:pull_request",
          "audiences":["api://AzureADTokenExchange"]
        }'

    Plan-first: without -Apply nothing is mutated; the script prints the
    exact command and, when an az session is available, whether the subject
    already exists. Idempotent: an existing credential with the same subject
    is verified (issuer + audience) and creation is skipped. After -Apply the
    credential list is read back via `az ad app federated-credential list`
    and the exact subject is asserted.

    CONTRACT GUARD (docs/CROSS-DOMAIN-CONTRACTS.md #2): the `pull_request`
    OIDC subject belongs EXCLUSIVELY to the read-only plan SP. Before doing
    anything, this script reads the target identity's Azure role assignments
    and REFUSES to proceed if the app holds Contributor, Owner, or User
    Access Administrator -- that means it was pointed at the Contributor app,
    and adding the credential there would break the plan/apply privilege
    split. Use -ExpectedRole (default: Reader) to additionally assert the
    role the plan SP is supposed to hold.

.PARAMETER AppId
    Application (client) ID -- or object ID -- of the PLAN app registration.
    This is the value stored in the AZURE_PLAN_CLIENT_ID repository secret.
    (It cannot be resolved automatically: GitHub never returns secret values,
    so the operator must supply it.)

.PARAMETER Repository
    GitHub repository as <owner>/<name> whose pull requests must be able to
    exchange OIDC tokens. Forms the subject `repo:<owner>/<name>:pull_request`.

.PARAMETER CredentialName
    Name for the federated credential record. Defaults to 'pr-plan' (the name the
    REVIEW.md §1 identity-estate blocker documents).

.PARAMETER ExpectedRole
    Role the target identity is expected to hold (sanity read-back). Defaults
    to 'Reader'. A missing expected role is a WARNING; a write-capable role
    (Contributor / Owner / User Access Administrator) is always a hard
    REFUSAL regardless of this parameter.

.PARAMETER SkipRoleCheck
    Skip the role-assignment contract guard. Only for environments where the
    signed-in principal cannot read role assignments; you are then personally
    asserting that AppId is the plan app, not the Contributor app.

.PARAMETER Apply
    Perform the mutation. Without it the script is read-only.

.EXAMPLE
    ./scripts/Add-PlanFederatedCredential.ps1 -AppId 00000000-0000-0000-0000-000000000000 `
        -Repository saulpatinojr/HCW-Plan_LZDeployment

    Plan only: prints the exact `az ad app federated-credential create`
    command and reports whether the subject already exists.

.EXAMPLE
    ./scripts/Add-PlanFederatedCredential.ps1 -AppId $planAppId `
        -Repository clientorg/lz-factory -Apply

    Creates the credential (if absent) and asserts the exact subject by API
    read-back.

.NOTES
    Requires: az CLI with a signed-in session. Creating federated credentials
    on an app registration requires the Entra role APPLICATION ADMINISTRATOR
    (or Cloud Application Administrator, or ownership of the app
    registration). Reading role assignments for the contract guard requires
    Reader on the relevant scope.

    This script never handles client secrets or tokens; federated identity
    is the point -- there is nothing to store.
#>
# CredentialName is the DISPLAY NAME of the federated identity record, not a
# secret; federated credentials are the secretless alternative to passwords.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialName')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$AppId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[\w.-]+$')]
    [string]$Repository,

    [string]$CredentialName = 'pr-plan',

    [string]$ExpectedRole = 'Reader',

    [switch]$SkipRoleCheck,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issuer = 'https://token.actions.githubusercontent.com'
$audience = 'api://AzureADTokenExchange'
$subject = "repo:${Repository}:pull_request"
$forbiddenRoles = @('Contributor', 'Owner', 'User Access Administrator')

function Invoke-LzAzJson {
    <#
    .SYNOPSIS
        Invokes az with JSON output and returns the parsed object.
        Throws with the real az error text on failure.
    #>
    param([Parameter(Mandatory)][string[]]$AzArguments)
    $raw = & az @AzArguments --output json 2>&1
    $exit = $LASTEXITCODE
    $text = ($raw | ForEach-Object { "$_" }) -join "`n"
    if ($exit -ne 0) {
        throw "az $($AzArguments -join ' ') failed (exit $exit): $text"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json -Depth 20
}

function Get-LzJsonProperty {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

# --- Preflight ---------------------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'The Azure CLI (az) is required and was not found on PATH.'
}

$mode = if ($Apply) { 'APPLY' } else { 'PLAN (read-only; supply -Apply to mutate)' }
Write-Host ('Add-PlanFederatedCredential -- mode: {0}' -f $mode)
Write-Host ('  App ID:   {0}' -f $AppId)
Write-Host ('  Subject:  {0}' -f $subject)
Write-Host ('  Issuer:   {0}' -f $issuer)
Write-Host ('  Audience: {0}' -f $audience)

$sessionAvailable = $true
try {
    Invoke-LzAzJson -AzArguments @('account', 'show') | Out-Null
}
catch {
    $sessionAvailable = $false
    if ($Apply) {
        throw 'No Azure CLI session (az account show failed). Run az login before -Apply.'
    }
    Write-Warning 'No Azure CLI session -- plan output only; existing-credential and role read-backs skipped.'
}

# --- Contract guard: refuse the Contributor app ------------------------------
if ($sessionAvailable -and -not $SkipRoleCheck) {
    Write-Host ''
    Write-Host '=== Contract guard (plan SP only -- CROSS-DOMAIN-CONTRACTS #2) ==='
    $roleAssignments = $null
    try {
        $roleAssignments = Invoke-LzAzJson -AzArguments @(
            'role', 'assignment', 'list', '--assignee', $AppId, '--all',
            '--query', '[].roleDefinitionName'
        )
    }
    catch {
        if ($Apply) {
            throw ("Could not read role assignments for {0} ({1}). The contract guard fails closed: verify the app is the PLAN identity, or re-run with -SkipRoleCheck if you have verified it out-of-band." -f $AppId, $_.Exception.Message)
        }
        Write-Warning ('Could not read role assignments for {0}: {1}' -f $AppId, $_.Exception.Message)
    }

    if ($null -ne $roleAssignments) {
        $roles = @($roleAssignments | Sort-Object -Unique)
        Write-Host ('  Roles held: {0}' -f $(if ($roles.Count) { $roles -join ', ' } else { '(none visible)' }))

        $writeCapable = @($roles | Where-Object { $_ -in $forbiddenRoles })
        if ($writeCapable.Count -gt 0) {
            throw ("REFUSED: {0} holds write-capable role(s) [{1}] -- this is the CONTRIBUTOR identity, not the read-only plan SP. The pull_request OIDC subject belongs exclusively to the plan SP (AZURE_PLAN_CLIENT_ID); adding it here would let any PR obtain write-capable Azure tokens. Point -AppId at the plan app registration." -f $AppId, ($writeCapable -join ', '))
        }
        if ($ExpectedRole -and ($roles -notcontains $ExpectedRole)) {
            Write-Warning ("Expected role '{0}' not found on {1} (found: {2}). Confirm this is the plan SP before applying." -f $ExpectedRole, $AppId, $(if ($roles.Count) { $roles -join ', ' } else { 'none' }))
        }
        elseif ($ExpectedRole) {
            Write-Host ('  Expected role ''{0}'': present.' -f $ExpectedRole)
        }
    }
}
elseif ($SkipRoleCheck) {
    Write-Warning 'Role-assignment contract guard SKIPPED (-SkipRoleCheck): you are asserting this is the plan app, not the Contributor app.'
}

# --- Idempotency read: does the subject already exist? -----------------------
$existing = $null
if ($sessionAvailable) {
    $credentialList = @(Invoke-LzAzJson -AzArguments @('ad', 'app', 'federated-credential', 'list', '--id', $AppId))
    Write-Host ''
    Write-Host ('=== Existing federated credentials on {0} ===' -f $AppId)
    if ($credentialList.Count -eq 0) {
        Write-Host '  (none)'
    }
    foreach ($credential in $credentialList) {
        Write-Host ('  - {0}: subject={1}' -f (Get-LzJsonProperty $credential 'name' '?'), (Get-LzJsonProperty $credential 'subject' '?'))
    }
    $existing = $credentialList | Where-Object { (Get-LzJsonProperty $_ 'subject' '') -eq $subject } | Select-Object -First 1
}

$parameters = [ordered]@{
    name      = $CredentialName
    issuer    = $issuer
    subject   = $subject
    audiences = @($audience)
}
$parametersJson = $parameters | ConvertTo-Json -Depth 5 -Compress

if ($null -ne $existing) {
    Write-Host ''
    Write-Host ('A federated credential with subject "{0}" already exists (name: {1}) -- creation will be skipped (idempotent).' -f $subject, (Get-LzJsonProperty $existing 'name' '?'))
    $existingIssuer = [string](Get-LzJsonProperty $existing 'issuer' '')
    $existingAudiences = @(Get-LzJsonProperty $existing 'audiences' @())
    if ($existingIssuer -ne $issuer -or ($existingAudiences -notcontains $audience)) {
        # Write-Host, not Write-Error: with $ErrorActionPreference = 'Stop' a
        # Write-Error would throw and make the exit 1 unreachable.
        Write-Host ("ERROR: existing credential has WRONG issuer/audience (issuer='{0}', audiences='{1}'). Expected issuer='{2}', audience='{3}'. Fix it with: az ad app federated-credential update --id {4} --federated-credential-id {5} --parameters '{6}'" -f $existingIssuer, ($existingAudiences -join ','), $issuer, $audience, $AppId, (Get-LzJsonProperty $existing 'id' '<id>'), $parametersJson)
        exit 1
    }
}

# --- Plan output -------------------------------------------------------------
Write-Host ''
Write-Host '=== Remediation command ==='
Write-Host ("  az ad app federated-credential create --id {0} --parameters '{1}'" -f $AppId, $parametersJson)

if (-not $Apply) {
    Write-Host ''
    if ($null -ne $existing) {
        Write-Host 'Plan: no change required -- the subject already exists with the correct issuer and audience.'
    }
    else {
        Write-Host 'Plan: 1 change pending (create the credential above). Re-run with -Apply to make it.'
    }
    exit 0
}

# --- Apply -------------------------------------------------------------------
if ($null -eq $existing) {
    Write-Host ''
    Write-Host 'Creating federated credential...'
    $temp = New-TemporaryFile
    try {
        $parameters | ConvertTo-Json -Depth 5 | Set-Content $temp -Encoding utf8
        Invoke-LzAzJson -AzArguments @(
            'ad', 'app', 'federated-credential', 'create',
            '--id', $AppId, '--parameters', "@$($temp.FullName)"
        ) | Out-Null
    }
    finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }
}

# --- Read-back assertion -----------------------------------------------------
Write-Host ''
Write-Host '=== Verification (API read-back) ==='
$verifyList = @(Invoke-LzAzJson -AzArguments @('ad', 'app', 'federated-credential', 'list', '--id', $AppId))
$verified = $verifyList | Where-Object { (Get-LzJsonProperty $_ 'subject' '') -eq $subject } | Select-Object -First 1

if ($null -eq $verified) {
    # Write-Host, not Write-Error (see note above).
    Write-Host ("ERROR: VERIFICATION FAILED -- no federated credential with subject '{0}' exists on {1} after apply." -f $subject, $AppId)
    exit 1
}

$verifiedIssuer = [string](Get-LzJsonProperty $verified 'issuer' '')
$verifiedAudiences = @(Get-LzJsonProperty $verified 'audiences' @())
$issuerOk = $verifiedIssuer -eq $issuer
$audienceOk = $verifiedAudiences -contains $audience

[pscustomobject]@{ Setting = 'subject'; Expected = $subject; Actual = (Get-LzJsonProperty $verified 'subject' ''); Status = 'OK' },
[pscustomobject]@{ Setting = 'issuer'; Expected = $issuer; Actual = $verifiedIssuer; Status = $(if ($issuerOk) { 'OK' } else { 'MISMATCH' }) },
[pscustomobject]@{ Setting = 'audiences'; Expected = $audience; Actual = ($verifiedAudiences -join ', '); Status = $(if ($audienceOk) { 'OK' } else { 'MISMATCH' }) } |
    Format-Table -AutoSize | Out-String | Write-Host

if (-not ($issuerOk -and $audienceOk)) {
    # Write-Host, not Write-Error (see note above).
    Write-Host 'ERROR: VERIFICATION FAILED -- issuer or audience does not match the required values.'
    exit 1
}

Write-Host ('Verified: subject "{0}" is live on app {1}. PR-triggered Azure OIDC logins for {2} can now exchange tokens as the plan SP.' -f $subject, $AppId, $Repository)
exit 0
