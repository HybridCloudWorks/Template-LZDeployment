#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The renderer owns layer derivation (Get-LzActiveLayers). Stage 11 consumes it
# rather than keeping a divergent copy, so an Adopt classification is validated
# against exactly the layers the renderer will emit.
Import-Module (Join-Path $PSScriptRoot '../renderer/LZFactory.Renderer.psd1') -Force -ErrorAction Stop

function Write-LzImportEvent {
    param([string]$Level, [string]$Message)
    $colour = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $colour
}

function Get-LzImportProperty {
    param([object]$Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Get-LzImportHash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LzImportTextHash {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function ConvertTo-LzImportResourceId {
    param(
        [Parameter(Mandatory)][string]$Probe,
        [Parameter(Mandatory)][object]$Item
    )
    $id = "$(Get-LzImportProperty $Item 'Id' '')"
    if ($id) { return $id }
    $name = "$(Get-LzImportProperty $Item 'Name' '')"
    $subscription = "$(Get-LzImportProperty $Item 'SubscriptionId' '')"
    $resourceGroup = "$(Get-LzImportProperty $Item 'ResourceGroup' '')"
    $scope = "$(Get-LzImportProperty $Item 'Scope' '')".TrimEnd('/')
    switch ($Probe) {
        'Resource groups' {
            if ($subscription -and $name) { return "/subscriptions/$subscription/resourceGroups/$name" }
        }
        'Virtual networks' {
            if ($subscription -and $resourceGroup -and $name) {
                return "/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Network/virtualNetworks/$name"
            }
        }
        'Log Analytics workspaces' {
            if ($subscription -and $resourceGroup -and $name) {
                return "/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$name"
            }
        }
        'Key vaults' {
            if ($subscription -and $resourceGroup -and $name) {
                return "/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.KeyVault/vaults/$name"
            }
        }
        'Policy assignments' {
            if ($scope -and $name) {
                return "$scope/providers/Microsoft.Authorization/policyAssignments/$name"
            }
        }
    }
    return ''
}

function Get-LzBrownfieldCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Discovery)

    if ((Get-LzImportProperty $Discovery 'readOnly' $false) -ne $true) {
        throw 'Discovery inventory must assert readOnly=true.'
    }
    $domains = Get-LzImportProperty $Discovery 'domains'
    $azure = Get-LzImportProperty $domains 'Azure'
    if (-not $azure) { throw 'Discovery inventory has no Azure domain.' }
    $probes = Get-LzImportProperty $azure 'probes'
    if (-not $probes) { throw 'Discovery inventory has no Azure probes.' }

    $supported = @(
        'Management groups',
        'Resource groups',
        'Virtual networks',
        'Log Analytics workspaces',
        'Key vaults',
        'Policy assignments'
    )
    $candidates = @()
    foreach ($probeName in $supported) {
        $probe = Get-LzImportProperty $probes $probeName
        if (-not $probe) { throw "Required discovery probe is absent: $probeName" }
        $conclusive = Get-LzImportProperty $probe 'conclusive' $false
        $status = "$(Get-LzImportProperty $probe 'status' '')"
        if (-not $conclusive -or $status -notin @('Ok', 'Empty')) {
            throw "Discovery probe is inconclusive: $probeName ($status). Inaccessible inventory cannot be classified as empty."
        }
        foreach ($item in @(Get-LzImportProperty $probe 'items' @())) {
            $id = ConvertTo-LzImportResourceId -Probe $probeName -Item $item
            if (-not $id) {
                throw "Cannot derive a stable Azure resource ID for an item in '$probeName'. Refresh discovery before classification."
            }
            $candidates += [pscustomobject]@{
                id = $id
                probe = $probeName
                name = "$(Get-LzImportProperty $item 'Name' (Get-LzImportProperty $item 'DisplayName' ''))"
                subscriptionId = "$(Get-LzImportProperty $item 'SubscriptionId' '')"
                resourceGroup = "$(Get-LzImportProperty $item 'ResourceGroup' '')"
                location = "$(Get-LzImportProperty $item 'Location' '')"
            }
        }
    }
    $duplicates = @($candidates | Group-Object { $_.id.ToLowerInvariant() } | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "Discovery inventory contains duplicate candidate IDs: $($duplicates.Name -join ', ')"
    }
    return @($candidates | Sort-Object id)
}

function New-LzBrownfieldClassificationTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Candidates,
        [Parameter(Mandatory)][string]$InventorySha256,
        [string]$DefaultClassification = 'ignore'
    )
    [ordered]@{
        schemaVersion = '1.0.0'
        inventorySha256 = $InventorySha256
        resources = @($Candidates | ForEach-Object {
            [ordered]@{
                id = $_.id
                classification = $DefaultClassification
                terraformAddress = ''
                layer = ''
                approvalReference = ''
                notes = "Discovered by $($_.probe). Review explicitly; Adopt requires an exact Terraform address and layer."
            }
        })
    }
}

function Test-LzTerraformAddress {
    param([string]$Address)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $false }
    return $Address -match '^(?:module\.[A-Za-z0-9_-]+(?:\[[^\r\n]+\])?\.)*[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+(?:\[[^\r\n]+\])?$'
}

function Resolve-LzBrownfieldClassifications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Candidates,
        [Parameter(Mandatory)][object]$Classification,
        [Parameter(Mandatory)][string]$InventorySha256,
        [Parameter(Mandatory)][string[]]$Layers,
        [string]$DefaultClassification = 'ignore',
        [switch]$AllowStaleInventory
    )

    if ("$(Get-LzImportProperty $Classification 'schemaVersion' '')" -ne '1.0.0') {
        throw 'Classification schemaVersion must be 1.0.0.'
    }
    $pinnedHash = "$(Get-LzImportProperty $Classification 'inventorySha256' '')".ToLowerInvariant()
    if ($pinnedHash -ne $InventorySha256 -and -not $AllowStaleInventory) {
        throw 'Classification inventorySha256 does not match discovery-inventory.json. Refresh classifications or use the documented owner-approved stale-inventory exception.'
    }

    $candidateMap = @{}
    foreach ($candidate in $Candidates) { $candidateMap[$candidate.id.ToLowerInvariant()] = $candidate }
    $explicitMap = @{}
    foreach ($entry in @(Get-LzImportProperty $Classification 'resources' @())) {
        $id = "$(Get-LzImportProperty $entry 'id' '')"
        if (-not $id) { throw 'Every classification entry requires an id.' }
        $key = $id.ToLowerInvariant()
        if ($explicitMap.ContainsKey($key)) { throw "Duplicate classification: $id" }
        if (-not $candidateMap.ContainsKey($key)) { throw "Classification references a resource absent from discovery: $id" }
        $explicitMap[$key] = $entry
    }

    $resolved = @()
    foreach ($candidate in $Candidates) {
        $key = $candidate.id.ToLowerInvariant()
        $entry = if ($explicitMap.ContainsKey($key)) { $explicitMap[$key] } else { $null }
        $classificationName = "$(Get-LzImportProperty $entry 'classification' $DefaultClassification)".ToLowerInvariant()
        if ($classificationName -notin @('adopt', 'ignore', 'replace', 'require-approval')) {
            throw "Unsupported classification '$classificationName' for $($candidate.id)."
        }
        $address = "$(Get-LzImportProperty $entry 'terraformAddress' '')"
        $layer = "$(Get-LzImportProperty $entry 'layer' '')"
        $approval = "$(Get-LzImportProperty $entry 'approvalReference' '')"
        $isExplicit = $null -ne $entry
        if ($classificationName -eq 'adopt') {
            if (-not $isExplicit) {
                throw "Default Adopt is not sufficient for $($candidate.id); add an explicit classification with Terraform address and layer."
            }
            if (-not (Test-LzTerraformAddress $address)) {
                throw "Adopt requires a valid exact Terraform address: $($candidate.id)"
            }
            if ($layer -notin $Layers) {
                throw "Adopt layer '$layer' is not active for $($candidate.id). Active layers: $($Layers -join ', ')"
            }
        }
        if ($classificationName -in @('replace', 'require-approval') -and [string]::IsNullOrWhiteSpace($approval)) {
            throw "$classificationName requires approvalReference: $($candidate.id)"
        }
        $resolved += [pscustomobject]@{
            id = $candidate.id
            probe = $candidate.probe
            name = $candidate.name
            classification = $classificationName
            terraformAddress = $address
            layer = $layer
            approvalReference = $approval
            notes = "$(Get-LzImportProperty $entry 'notes' '')"
            explicit = $isExplicit
        }
    }
    return $resolved
}

function ConvertTo-LzHclQuoted {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + ($Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n')) + '"'
}

function ConvertTo-LzShellSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)
    $quote = [string][char]39
    $doubleQuote = [string][char]34
    $replacement = $quote + $doubleQuote + $quote + $doubleQuote + $quote
    return $quote + $Value.Replace($quote, $replacement) + $quote
}

function New-LzBrownfieldArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Resolved,
        [bool]$GenerateImportBlocks = $true,
        [bool]$GenerateImportCommands = $true
    )
    $artifacts = @()
    $adopted = @($Resolved | Where-Object classification -eq 'adopt')
    foreach ($group in @($adopted | Group-Object layer | Sort-Object Name)) {
        $layer = $group.Name
        $items = @($group.Group | Sort-Object terraformAddress)
        if ($GenerateImportBlocks) {
            $lines = @(
                '# GENERATED by Landing Zone Factory Stage 11. Review before plan.'
                '# No import is executed by this file; Terraform evaluates it during plan/apply.'
                ''
            )
            foreach ($item in $items) {
                $lines += 'import {'
                $lines += "  to = $($item.terraformAddress)"
                $lines += "  id = $(ConvertTo-LzHclQuoted $item.id)"
                $lines += '}'
                $lines += ''
            }
            $artifacts += [pscustomobject]@{
                path = "terraform/live/$layer/imports.generated.tf"
                kind = 'import-blocks'
                content = ($lines -join "`n")
            }
        }
        if ($GenerateImportCommands) {
            $lines = @(
                '#!/usr/bin/env bash'
                'set -euo pipefail'
                ''
                '# GENERATED REVIEW ARTIFACT. This script is never executed by the factory.'
                '# Run only after approving the matching plan and state backup.'
            )
            foreach ($item in $items) {
                $lines += "terraform -chdir=$(ConvertTo-LzShellSingleQuoted "terraform/live/$layer") import $(ConvertTo-LzShellSingleQuoted $item.terraformAddress) $(ConvertTo-LzShellSingleQuoted $item.id)"
            }
            $artifacts += [pscustomobject]@{
                path = "scripts/import-$layer.generated.sh"
                kind = 'import-commands'
                content = ($lines -join "`n") + "`n"
            }
        }
    }
    return $artifacts
}

function Set-LzBrownfieldArtifacts {
    param(
        [Parameter(Mandatory)][string]$RenderedDirectory,
        [Parameter(Mandatory)][object[]]$Artifacts
    )
    $manifestPath = Join-Path $RenderedDirectory 'render-manifest.json'
    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        throw "Stage 10 renderer manifest not found: $manifestPath"
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json -Depth 40
    $oldArtifacts = @($manifest.files | Where-Object { "$($_.Source)" -like 'stage11:*' })
    foreach ($old in $oldArtifacts) {
        $oldDestination = "$($old.Destination)" -replace '\\', '/'
        if ($oldDestination -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($oldDestination)) {
            throw "Unsafe prior Stage 11 manifest destination: $oldDestination"
        }
        $oldPath = Join-Path $RenderedDirectory $oldDestination
        if (Test-Path $oldPath -PathType Leaf) { Remove-Item $oldPath -Force }
    }
    $existing = @($manifest.files | Where-Object { "$($_.Source)" -notlike 'stage11:*' })
    foreach ($artifact in $Artifacts) {
        $path = Join-Path $RenderedDirectory $artifact.path
        $directory = Split-Path -Parent $path
        if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        Set-Content $path -Value $artifact.content -Encoding utf8 -NoNewline
        $existing += [pscustomobject]@{
            Source = "stage11:$($artifact.kind)"
            Destination = $artifact.path
            Mode = 'generated'
        }
    }
    $manifest.files = @($existing | Sort-Object Destination)
    $manifest.fileCount = $manifest.files.Count
    $manifest | ConvertTo-Json -Depth 40 | Set-Content $manifestPath -Encoding utf8
}

function Invoke-LzBrownfieldImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$DiscoveryPath,
        [Parameter(Mandatory)][string]$ClassificationPath,
        [Parameter(Mandatory)][string]$RenderedDirectory,
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [switch]$Apply,
        [switch]$AllowStaleInventory
    )
    foreach ($path in @($ConfigPath, $DiscoveryPath)) {
        if (-not (Test-Path $path -PathType Leaf)) { throw "Required input not found: $path" }
    }
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -Depth 50
    if ("$($config.deploymentStrategy.mode)" -ne 'brownfield') {
        throw 'Stage 11 import generation requires deploymentStrategy.mode=brownfield.'
    }
    $discovery = Get-Content $DiscoveryPath -Raw | ConvertFrom-Json -Depth 50
    if ("$(Get-LzImportProperty $discovery 'factoryVersion' '')" -ne "$($config.factoryVersion)") {
        throw "Discovery/config factory version mismatch: $(Get-LzImportProperty $discovery 'factoryVersion' '') != $($config.factoryVersion)"
    }
    $inventoryHash = Get-LzImportHash $DiscoveryPath
    $candidates = @(Get-LzBrownfieldCandidates -Discovery $discovery)
    $brownfield = Get-LzImportProperty $config.deploymentStrategy 'brownfield' ([pscustomobject]@{})
    $defaultClassification = "$(Get-LzImportProperty $brownfield 'defaultClassification' 'ignore')"
    # Single source of truth: the renderer's layer derivation (control AR3).
    $layers = @(Get-LzActiveLayers -Config $config)

    New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
    $template = New-LzBrownfieldClassificationTemplate -Candidates $candidates `
        -InventorySha256 $inventoryHash -DefaultClassification $defaultClassification
    $templatePath = Join-Path $EvidenceDirectory 'brownfield-classifications.generated.json'
    $template | ConvertTo-Json -Depth 20 | Set-Content $templatePath -Encoding utf8

    $classification = if (Test-Path $ClassificationPath -PathType Leaf) {
        Get-Content $ClassificationPath -Raw | ConvertFrom-Json -Depth 30
    } else {
        [pscustomobject]$template
    }
    $resolved = @(Resolve-LzBrownfieldClassifications -Candidates $candidates `
        -Classification $classification -InventorySha256 $inventoryHash `
        -Layers $layers -DefaultClassification $defaultClassification `
        -AllowStaleInventory:$AllowStaleInventory)

    $generateBlocks = [bool](Get-LzImportProperty $brownfield 'generateImportBlocks' $true)
    $generateCommands = [bool](Get-LzImportProperty $brownfield 'generateImportCommands' $true)
    $artifacts = @(New-LzBrownfieldArtifacts -Resolved $resolved `
        -GenerateImportBlocks $generateBlocks -GenerateImportCommands $generateCommands)
    $plan = [ordered]@{
        schemaVersion = '1.0.0'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = 'plan'
        inventorySha256 = $inventoryHash
        inventoryGeneratedAt = (Get-LzImportProperty $discovery 'generatedAt' '')
        staleInventoryException = [bool]$AllowStaleInventory
        defaultClassification = $defaultClassification
        candidateCount = $candidates.Count
        adoptCount = @($resolved | Where-Object classification -eq 'adopt').Count
        ignoreCount = @($resolved | Where-Object classification -eq 'ignore').Count
        replaceCount = @($resolved | Where-Object classification -eq 'replace').Count
        requireApprovalCount = @($resolved | Where-Object classification -eq 'require-approval').Count
        resources = $resolved
        artifacts = @($artifacts | ForEach-Object {
            [ordered]@{
                path = $_.path
                kind = $_.kind
                sha256 = (Get-LzImportTextHash $_.content)
            }
        })
        executesTerraformImport = $false
    }
    $planPath = Join-Path $EvidenceDirectory 'brownfield-import-plan.json'
    $plan | ConvertTo-Json -Depth 30 | Set-Content $planPath -Encoding utf8
    $pending = @()
    foreach ($item in @($resolved | Where-Object classification -in @('replace', 'require-approval'))) {
        $pending += "Review $($item.classification) resource $($item.id) under approval $($item.approvalReference); no mutation was generated."
    }
    if (-not (Test-Path $ClassificationPath -PathType Leaf)) {
        $pending += "Review $templatePath and save approved classifications to $ClassificationPath."
    }

    $audit = [ordered]@{
        schemaVersion = '1.0.0'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        mode = if ($Apply) { 'apply' } else { 'plan' }
        applied = $false
        inventorySha256 = $inventoryHash
        emitted = @()
        manifestUpdated = $false
        executesTerraformImport = $false
        pendingUserActivities = $pending
        error = $null
    }
    if ($Apply) {
        if (-not (Test-Path $ClassificationPath -PathType Leaf)) {
            throw "Apply requires an operator-owned classification file: $ClassificationPath"
        }
        try {
            Set-LzBrownfieldArtifacts -RenderedDirectory $RenderedDirectory -Artifacts $artifacts
            $audit.applied = $true
            $audit.manifestUpdated = $true
            $audit.emitted = @($artifacts | ForEach-Object { $_.path })
            Write-LzImportEvent OK "Generated $($artifacts.Count) review artifact(s); Terraform import was not executed."
        }
        catch {
            $audit.error = $_.Exception.Message
            $audit.pendingUserActivities += 'Resolve the recorded error and re-run the idempotent Stage 11 generator.'
            $auditPath = Join-Path $EvidenceDirectory 'brownfield-import-audit.json'
            $audit | ConvertTo-Json -Depth 20 | Set-Content $auditPath -Encoding utf8
            throw
        }
    }
    else {
        $audit.pendingUserActivities += 'Review brownfield-import-plan.json and set LZ_IMPORT_APPLY=true only after classifications are approved.'
        Write-LzImportEvent OK "Plan complete: $planPath"
        Write-LzImportEvent WARN 'No rendered tree or Terraform state was modified.'
    }
    $auditPath = Join-Path $EvidenceDirectory 'brownfield-import-audit.json'
    $audit | ConvertTo-Json -Depth 20 | Set-Content $auditPath -Encoding utf8
    return [pscustomobject]@{ Plan = [pscustomobject]$plan; Audit = [pscustomobject]$audit; PlanPath = $planPath; AuditPath = $auditPath }
}

Export-ModuleMember -Function @(
    'Get-LzBrownfieldCandidates'
    'New-LzBrownfieldClassificationTemplate'
    'Resolve-LzBrownfieldClassifications'
    'New-LzBrownfieldArtifacts'
    'Invoke-LzBrownfieldImport'
)
