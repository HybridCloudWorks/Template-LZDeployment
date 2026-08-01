#Requires -Version 7.0
<#
.SYNOPSIS
    Emits the per-layer backend.hcl files for the live stacks from the
    backend-bootstrap outputs, a wizard export, or explicit parameters.
.DESCRIPTION
    Replaces the "<REPLACE_WITH_OUTPUT_FROM_BOOTSTRAP>" placeholder flow: every
    stack under terraform/live/ needs a backend.hcl whose storage account name
    only exists after terraform/backend-bootstrap has applied, so terraform init
    fails until the value is filled in. This script fills it in deterministically.

    Non-interactive and plan-first, matching bootstrap-broker.ps1 and
    scaffold-copy.ps1: it prints exactly what each layer's backend.hcl would
    contain and writes nothing until -Apply (or LZ_BACKEND_APPLY=true) is
    supplied. Re-running against already-correct files reports them unchanged
    and rewrites nothing, so the script is idempotent.

    Backend values are resolved from exactly one source, in precedence order:

      1. -StorageAccountName / -ResourceGroupName (both required together).
         Layout: one state container per layer, key "terraform.tfstate" --
         the layout terraform/backend-bootstrap provisions and the layout the
         remote-state reads in terraform/live/workloads-prod/main.tf expect.
      2. -ConfigPath: a wizard-exported backend.hcl or lz-config.json.
         The wizard emits a single shared container with per-layer state keys
         ("<layer>.tfstate"), and that layout is preserved -- with a warning,
         because this repo's live remote-state reads expect layout 1.
      3. Default: `terraform output -json` from terraform/backend-bootstrap/
         (requires an initialized stack with applied state).

    use_azuread_auth is always written as true. The state storage account sets
    shared_access_key_enabled = false (cross-domain contract #3, AAD-only state
    access), so a backend.hcl without AAD auth cannot authenticate at init. A
    source that requests key auth is overridden with a warning, never honored.
.PARAMETER StorageAccountName
    State storage account name, as printed by the backend-bootstrap output of
    the same name. Requires -ResourceGroupName.
.PARAMETER ResourceGroupName
    Resource group containing the state storage account. Requires
    -StorageAccountName.
.PARAMETER ContainerName
    Single shared state container. When supplied, every layer gets this
    container and a per-layer key ("<layer>.tfstate") so layer states can
    never collide inside the shared container.
.PARAMETER ConfigPath
    Path to a wizard-exported backend.hcl or lz-config.json to read the
    backend values from. Mutually exclusive with -StorageAccountName /
    -ResourceGroupName / -ContainerName.
.PARAMETER BootstrapDirectory
    The backend-bootstrap stack directory queried with `terraform output -json`
    when no other source is supplied.
.PARAMETER LiveDirectory
    Root of the live stacks whose backend.hcl files are managed.
.PARAMETER Layer
    Subset of layers to emit. Defaults to every azurerm-backed live stack.
    The sandbox stack is deliberately absent: its backend.hcl is Terraform
    Cloud, not azurerm.
.PARAMETER Apply
    Write the files. Without it the script only prints the plan
    (LZ_BACKEND_APPLY=true is the environment equivalent).
.EXAMPLE
    pwsh -File scripts/New-BackendConfig.ps1
    Plans from the backend-bootstrap outputs; writes nothing.
.EXAMPLE
    pwsh -File scripts/New-BackendConfig.ps1 -StorageAccountName sttfstatescus01 -ResourceGroupName rg-tfstate-scus-prod-01 -Apply
    Writes all four live backend.hcl files from explicit values.
#>
[CmdletBinding()]
param(
    [string]$StorageAccountName,
    [string]$ResourceGroupName,
    [string]$ContainerName,
    [string]$ConfigPath = $env:LZ_BACKEND_CONFIG_PATH,
    [string]$BootstrapDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'terraform', 'backend-bootstrap'),
    [string]$LiveDirectory = (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'terraform', 'live'),
    [ValidateSet('global', 'platform-connectivity', 'platform-management', 'workloads-prod')]
    [string[]]$Layer = @('global', 'platform-connectivity', 'platform-management', 'workloads-prod'),
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The containers terraform/backend-bootstrap provisions for each live layer
# (mirrors its layer_state_containers output, used as the fallback when that
# output is not part of the source).
$defaultLayerContainers = @{
    'global'                = 'global-mgmt-groups'
    'platform-connectivity' = 'platform-connectivity'
    'platform-management'   = 'platform-management'
    'workloads-prod'        = 'workloads-prod'
}

function Test-LzStorageAccountName {
    param([Parameter(Mandatory)][string]$Name)
    return $Name -match '^[a-z0-9]{3,24}$'
}

function Get-LzBackendFromHcl {
    <# Parse the flat `key = "value"` lines of a wizard-exported backend.hcl. #>
    param([Parameter(Mandatory)][string]$Path)

    $raw = Get-Content -Path $Path -Raw
    if ($raw -match '(?m)^\s*(workspaces|organization|hostname)\b') {
        throw "'$Path' is an HCP Terraform backend export. This script only emits azurerm backend files; re-export the wizard configuration with the azurerm backend selected."
    }

    $values = @{}
    foreach ($name in 'resource_group_name', 'storage_account_name', 'container_name', 'use_azuread_auth') {
        if ($raw -match ('(?m)^\s*' + $name + '\s*=\s*"?([^"\r\n]+)"?\s*$')) {
            $values[$name] = $Matches[1].Trim()
        }
    }
    foreach ($required in 'resource_group_name', 'storage_account_name') {
        if (-not $values.ContainsKey($required)) {
            throw "'$Path' does not declare '$required'; it does not look like an azurerm backend.hcl."
        }
    }

    [pscustomobject]@{
        StorageAccountName = $values['storage_account_name']
        ResourceGroupName  = $values['resource_group_name']
        SharedContainer    = $values['container_name']
        RequestedAadAuth   = -not ($values.ContainsKey('use_azuread_auth') -and $values['use_azuread_auth'] -eq 'false')
        LayerContainers    = $null
        Origin             = "wizard backend.hcl ($Path)"
    }
}

function Get-LzBackendFromConfigJson {
    <# Read backend.azurerm out of a wizard-exported lz-config.json. #>
    param([Parameter(Mandatory)][string]$Path)

    $cfg = Get-Content -Path $Path -Raw | ConvertFrom-Json -Depth 20
    if (-not ($cfg.PSObject.Properties.Name -contains 'backend')) {
        throw "'$Path' has no 'backend' section; it does not look like an lz-config.json."
    }
    if ($cfg.backend.type -ne 'azurerm') {
        throw "'$Path' selects backend type '$($cfg.backend.type)'. This script only emits azurerm backend files."
    }

    $a = $cfg.backend.azurerm
    [pscustomobject]@{
        StorageAccountName = [string]$a.storageAccountName
        ResourceGroupName  = [string]$a.resourceGroupName
        SharedContainer    = [string]$a.containerName
        RequestedAadAuth   = [bool]$a.useAzureAdAuth
        LayerContainers    = $null
        Origin             = "lz-config.json ($Path)"
    }
}

function Get-LzBackendFromBootstrapOutput {
    <# Read the applied backend-bootstrap stack's outputs (read-only). #>
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path (Join-Path -Path $Directory -ChildPath 'main.tf'))) {
        throw "Backend-bootstrap stack not found at '$Directory'."
    }
    $json = terraform -chdir="$Directory" output -json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Reading 'terraform output -json' from '$Directory' failed (is the stack initialized and applied?):`n$json"
    }
    $outputs = "$json" | ConvertFrom-Json -Depth 10
    foreach ($required in 'storage_account_name', 'resource_group_name') {
        if (-not ($outputs.PSObject.Properties.Name -contains $required)) {
            throw "Bootstrap output '$required' is missing. Apply terraform/backend-bootstrap first."
        }
    }

    $layerContainers = $null
    if ($outputs.PSObject.Properties.Name -contains 'layer_state_containers') {
        $layerContainers = @{}
        foreach ($p in $outputs.layer_state_containers.value.PSObject.Properties) {
            $layerContainers[$p.Name] = [string]$p.Value
        }
    }

    [pscustomobject]@{
        StorageAccountName = [string]$outputs.storage_account_name.value
        ResourceGroupName  = [string]$outputs.resource_group_name.value
        SharedContainer    = ''
        RequestedAadAuth   = $true
        LayerContainers    = $layerContainers
        Origin             = "terraform output ($Directory)"
    }
}

# -- Resolve the single source of backend values -----------------------------
$explicitParams = @($StorageAccountName, $ResourceGroupName, $ContainerName).Where({ $_ })
if ($explicitParams.Count -gt 0 -and $ConfigPath) {
    throw 'Use either explicit parameters (-StorageAccountName/-ResourceGroupName/-ContainerName) or -ConfigPath, not both.'
}

if ($StorageAccountName -or $ResourceGroupName) {
    if (-not ($StorageAccountName -and $ResourceGroupName)) {
        throw '-StorageAccountName and -ResourceGroupName must be supplied together.'
    }
    $source = [pscustomobject]@{
        StorageAccountName = $StorageAccountName
        ResourceGroupName  = $ResourceGroupName
        SharedContainer    = $ContainerName
        RequestedAadAuth   = $true
        LayerContainers    = $null
        Origin             = 'explicit parameters'
    }
}
elseif ($ConfigPath) {
    if (-not (Test-Path $ConfigPath)) { throw "Config path not found: $ConfigPath" }
    $source = if ([IO.Path]::GetExtension($ConfigPath) -eq '.json') {
        Get-LzBackendFromConfigJson -Path $ConfigPath
    }
    else {
        Get-LzBackendFromHcl -Path $ConfigPath
    }
    if ($ContainerName) { $source.SharedContainer = $ContainerName }
}
else {
    $source = Get-LzBackendFromBootstrapOutput -Directory $BootstrapDirectory
}

if ($source.StorageAccountName -like '<*') {
    throw "Storage account name '$($source.StorageAccountName)' is still a placeholder. Apply terraform/backend-bootstrap and use its output."
}
if (-not (Test-LzStorageAccountName -Name $source.StorageAccountName)) {
    throw "'$($source.StorageAccountName)' is not a valid storage account name (3-24 chars, lowercase letters and digits)."
}
if (-not $source.ResourceGroupName) {
    throw 'Resource group name resolved empty.'
}

# AAD-only state access (cross-domain contract #3): the state storage account
# disables shared keys, so key auth can never work. Never honor a request to
# turn it off.
if (-not $source.RequestedAadAuth) {
    Write-Warning "The source requests use_azuread_auth = false, but the state storage account disables shared keys (contract #3). Writing use_azuread_auth = true regardless."
}

$sharedMode = [bool]$source.SharedContainer
if ($sharedMode) {
    Write-Warning ("Shared-container layout: all layers use container '{0}' with per-layer state keys." -f $source.SharedContainer)
    Write-Warning "This repo's live remote-state reads (terraform/live/workloads-prod/main.tf) expect the per-layer-container layout from backend-bootstrap; reconcile them before init if you apply this layout here."
}

# -- Build the plan -----------------------------------------------------------
$plan = foreach ($name in $Layer) {
    $container = if ($sharedMode) {
        $source.SharedContainer
    }
    elseif ($source.LayerContainers -and $source.LayerContainers.ContainsKey($name)) {
        $source.LayerContainers[$name]
    }
    else {
        $defaultLayerContainers[$name]
    }
    $key = if ($sharedMode) { "$name.tfstate" } else { 'terraform.tfstate' }

    # Exact shape of the committed live backend.hcl files, placeholder aside.
    $content = @(
        "resource_group_name  = `"$($source.ResourceGroupName)`""
        "storage_account_name = `"$($source.StorageAccountName)`""
        "container_name       = `"$container`""
        "key                  = `"$key`""
        ''
        'use_azuread_auth     = true'
        ''
    ) -join "`n"

    $path = Join-Path -Path $LiveDirectory -ChildPath $name -AdditionalChildPath 'backend.hcl'
    # Normalize line endings for the comparison so a CRLF checkout of an
    # already-correct file still counts as unchanged (idempotency).
    $state = if (-not (Test-Path $path)) { 'create' }
    elseif (((Get-Content -Path $path -Raw) -replace "`r`n", "`n") -ne $content) { 'update' }
    else { 'unchanged' }

    [pscustomobject]@{ Layer = $name; Path = $path; State = $state; Content = $content }
}

# -- Report, then write only under -Apply -------------------------------------
$applyRequested = $Apply -or $env:LZ_BACKEND_APPLY -eq 'true'
$mode = if ($applyRequested) { 'apply' } else { 'plan' }

Write-Output "New-BackendConfig ($mode) -- source: $($source.Origin)"
Write-Output "  storage_account_name = $($source.StorageAccountName)"
Write-Output "  resource_group_name  = $($source.ResourceGroupName)"
Write-Output ''

foreach ($entry in $plan) {
    Write-Output ("[{0}] {1} -> {2}" -f $entry.State, $entry.Layer, $entry.Path)
    if ($entry.State -ne 'unchanged') {
        foreach ($line in ($entry.Content -split "`n")) { Write-Output "    $line" }
    }
}

$pending = @($plan | Where-Object { $_.State -ne 'unchanged' })
if ($pending.Count -eq 0) {
    Write-Output ''
    Write-Output 'All backend.hcl files already match. Nothing to do.'
    return
}

if (-not $applyRequested) {
    Write-Output ''
    Write-Output ("Plan only: {0} file(s) would change. Re-run with -Apply (or LZ_BACKEND_APPLY=true) to write them." -f $pending.Count)
    return
}

foreach ($entry in $pending) {
    Set-Content -Path $entry.Path -Value $entry.Content -NoNewline -Encoding utf8NoBOM
    Write-Output ("Wrote {0}" -f $entry.Path)
}
Write-Output ''
Write-Output ("Done: {0} file(s) written. Run 'terraform init -backend-config=backend.hcl' in each layer to verify." -f $pending.Count)
