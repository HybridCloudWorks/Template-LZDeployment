#Requires -Version 7.0
<#
.SYNOPSIS
    Corpus-vs-broker resource-provider drift check (decision 0006).
.DESCRIPTION
    azurerm ~> 5.0 registers no resource providers, so the generated repos
    depend entirely on the broker registering the required namespaces at
    bootstrap (decision 0006, Option A). The namespace list lives in
    PowerShell, away from the Terraform that needs it — this check is the
    guard for that documented drift risk: it derives the distinct azurerm_*
    resource/data-source types from the template corpus, maps each to its ARM
    provider namespace, and fails when the broker's authoritative list
    (Get-LzRequiredResourceProviders) does not cover one. A template module
    adding a resource type must fail HERE, not at a client site mid-first-apply.

    Credential-free and network-free: reads source files only.
.PARAMETER TemplateRoot
    Terraform corpus to scan. Defaults to factory/templates/terraform; tests
    point it at seeded corpora to prove the failure modes.
.PARAMETER RequiredNamespaces
    TEST SEAM ONLY (Test-LzSchemaDrift precedent: every input injectable).
    Overrides the broker's required list so the seeded-mismatch test can prove
    the MISSING NAMESPACE branch fires. Production callers (Invoke-FactoryCI)
    never pass it — the authoritative list stays Get-LzRequiredResourceProviders.
#>
[CmdletBinding()]
param(
    [string]$TemplateRoot,
    [string[]]$RequiredNamespaces
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $TemplateRoot) { $TemplateRoot = Join-Path $repo 'factory/templates/terraform' }
if (-not (Test-Path $TemplateRoot -PathType Container)) {
    Write-Host "Template corpus not found: $TemplateRoot"
    exit 1
}

# ONE authoritative list and ONE mapping, both owned by the broker module —
# this check must never grow a second copy of either.
Import-Module (Join-Path $repo 'factory/bootstrap/LZFactory.Bootstrap.psm1') -Force

$providers = Get-LzRequiredResourceProviders
$required = if ($RequiredNamespaces) { @($RequiredNamespaces) } else { @($providers.required) }
$excluded = @($providers.excluded)

# Distinct azurerm_* types actually declared as resource or data blocks —
# .tf plus .tf.tmpl, so config-conditional template regions are the scanned
# superset of anything the renderer can emit.
$typePattern = '(?m)^\s*(?:resource|data)\s+"(azurerm_[a-z0-9_]+)"'
$resourceTypes = [System.Collections.Generic.SortedSet[string]]::new()
Get-ChildItem $TemplateRoot -Recurse -File |
    Where-Object { $_.Name -like '*.tf' -or $_.Name -like '*.tf.tmpl' } |
    ForEach-Object {
        foreach ($match in [regex]::Matches((Get-Content $_.FullName -Raw), $typePattern)) {
            $resourceTypes.Add($match.Groups[1].Value) | Out-Null
        }
    }

$failures = @()
$corpusNamespaces = [System.Collections.Generic.SortedSet[string]]::new()
foreach ($resourceType in $resourceTypes) {
    try {
        $namespace = Resolve-LzResourceTypeNamespace -ResourceType $resourceType
    }
    catch {
        # Unknown type: the mapping itself must be extended. The exception
        # message already names the exact extension points.
        $failures += "UNMAPPED TYPE: $($_.Exception.Message)"
        continue
    }
    if ($null -eq $namespace) { continue }  # provider-context data source, no namespace
    $corpusNamespaces.Add($namespace) | Out-Null
    if ($namespace -in $excluded) { continue }  # registered by default in every subscription
    if ($namespace -notin $required) {
        $failures += ("MISSING NAMESPACE: '$resourceType' needs '$namespace', which the broker does not register. " +
            "Add '$namespace' to Get-LzRequiredResourceProviders in factory/bootstrap/LZFactory.Bootstrap.psm1 " +
            'and record the extension against decision 0006 (docs/decisions/0006-resource-provider-registration.md).')
    }
}

Write-Host "Corpus: $($resourceTypes.Count) distinct azurerm_* types -> namespaces: $(@($corpusNamespaces) -join ', ')"
$extras = @($required | Where-Object { $_ -notin @($corpusNamespaces) })
if ($extras.Count -gt 0) {
    # Informational, never a failure: registering ahead of the corpus is
    # deliberate (Microsoft.KeyVault for the keyvault-cmk scaffold). Only the
    # reverse direction — corpus needs it, broker lacks it — fails a client.
    Write-Host "Broker registers ahead of the corpus (deliberate, not drift): $($extras -join ', ')"
}

if ($failures.Count -gt 0) {
    Write-Host "Resource-provider coverage FAILED with $($failures.Count) finding(s):"
    $failures | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host 'Every corpus namespace is covered by the broker registration list.'
exit 0
