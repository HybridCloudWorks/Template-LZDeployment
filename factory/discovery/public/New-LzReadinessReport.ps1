#Requires -Version 7.0
<#
    Report generation.

    Produces two artifacts:

      tenant-readiness-report.md  — the human gate before bootstrap runs.
      discovery-inventory.json    — the machine-readable inventory the broker
                                    and the brownfield import generator consume.

    Everything written here passes through Protect-LzSecretText. Discovery has
    no legitimate need to emit a credential, and these files routinely get
    pasted into tickets and chat, so redaction is applied on the way out rather
    than trusting every upstream CLI never to echo a token in an error message.
#>

Set-StrictMode -Version Latest

function New-LzReadinessReport {
    <#
    .SYNOPSIS
        Render tenant-readiness-report.md from a discovery run.
    .PARAMETER Discovery
        The object returned by Invoke-LzDiscovery.
    .PARAMETER Path
        Output file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Discovery,
        [Parameter(Mandatory)][string]$Path
    )

    $cfg = $Discovery.Config
    $readiness = $Discovery.Readiness
    $sb = [System.Text.StringBuilder]::new()
    $add = { param([string]$line) [void]$sb.AppendLine($line) }

    $company = if ($cfg) { $cfg.organization.companyName } else { '(no configuration supplied)' }
    $mode = if ($cfg) { $cfg.deploymentStrategy.mode } else { 'unknown' }

    & $add "# Tenant Readiness Report"
    & $add ''
    & $add "**Organization**: $company  "
    & $add "**Deployment mode**: $mode  "
    & $add "**Generated**: $($Discovery.GeneratedAt)  "
    & $add "**Factory version**: $($Discovery.FactoryVersion)  "
    & $add "**Discovery duration**: $([math]::Round($Discovery.DurationSeconds, 1))s"
    & $add ''
    & $add 'This report is produced by a read-only discovery run. Nothing was created, modified, or deleted.'
    & $add ''

    # ── Verdict ──────────────────────────────────────────────────────────────
    & $add '---'
    & $add ''
    & $add '## Verdict'
    & $add ''

    if ($readiness) {
        if ($readiness.FailCount -gt 0) {
            & $add "> **NOT READY** — $($readiness.FailCount) check(s) failed. Bootstrap will not succeed until these are resolved."
        }
        elseif ($readiness.WarningCount -gt 0) {
            & $add "> **READY WITH CAVEATS** — no failures, but $($readiness.WarningCount) check(s) need a decision from you before proceeding."
        }
        else {
            & $add '> **READY** — all readiness checks passed.'
        }
        & $add ''
        & $add "| Result | Count |"
        & $add "|---|---|"
        & $add "| Pass | $($readiness.PassCount) |"
        & $add "| Warning | $($readiness.WarningCount) |"
        & $add "| Fail | $($readiness.FailCount) |"
    }
    else {
        & $add '> Readiness checks did not run. This report contains inventory only.'
    }
    & $add ''

    # ── Readiness detail ─────────────────────────────────────────────────────
    if ($readiness) {
        & $add '---'
        & $add ''
        & $add '## Readiness checks'
        & $add ''
        & $add 'A **Warning** means the capability could not be confirmed, or is present with a caveat. It is deliberately distinct from **Pass**: "I could not check" and "this is fine" are different answers and are never rendered the same way.'
        & $add ''
        & $add '| # | Check | Category | Status | Detail |'
        & $add '|---|---|---|---|---|'
        foreach ($c in $readiness.Checks) {
            $icon = switch ($c.Status) { 'Pass' { '✅ Pass' } 'Warning' { '⚠️ Warning' } 'Fail' { '❌ Fail' } }
            & $add ("| {0} | {1} | {2} | {3} | {4} |" -f `
                $c.Id, (ConvertTo-LzSafeString $c.Name), $c.Category, $icon, (ConvertTo-LzSafeString $c.Detail))
        }
        & $add ''

        $needsAction = @($readiness.Checks | Where-Object { $_.Status -ne 'Pass' -and $_.Remediation })
        if ($needsAction.Count -gt 0) {
            & $add '### Remediation'
            & $add ''
            foreach ($c in $needsAction) {
                $label = if ($c.Status -eq 'Fail') { 'BLOCKING' } else { 'Advisory' }
                & $add "#### $($c.Id) — $($c.Name) *($label)*"
                & $add ''
                & $add (ConvertTo-LzSafeString $c.Detail)
                & $add ''
                & $add "**Resolution**: $(ConvertTo-LzSafeString $c.Remediation)"
                & $add ''
            }
        }
    }

    # ── Deployment-mode challenge ────────────────────────────────────────────
    $azure = $Discovery.Azure
    if ($azure -and $azure.ExistingLandingZone -and $azure.ExistingLandingZone.LikelyExisting) {
        & $add '---'
        & $add ''
        & $add '## Existing landing zone detected'
        & $add ''
        if ($mode -eq 'greenfield') {
            & $add '> **This tenant does not look empty, but the configuration declares `greenfield`.**'
            & $add '>'
            & $add '> A greenfield run adds to what is already here rather than replacing it. Review the signals below and switch to `brownfield` if any of them describe infrastructure you intend to keep.'
        }
        else {
            & $add 'Consistent with the declared `brownfield` mode. The signals below inform the import and adoption plan.'
        }
        & $add ''
        foreach ($s in $azure.ExistingLandingZone.Signals) { & $add "- $(ConvertTo-LzSafeString $s)" }
        & $add ''
    }

    # ── Address collisions ───────────────────────────────────────────────────
    if ($azure -and @($azure.AddressCollisions).Count -gt 0) {
        & $add '---'
        & $add ''
        & $add '## Address space collisions'
        & $add ''
        & $add 'Overlapping ranges cannot be peered. This failure surfaces only after the virtual networks have been created, so it is far cheaper to resolve now.'
        & $add ''
        & $add '| Planned CIDR | Conflicting VNet | Existing CIDR | Subscription |'
        & $add '|---|---|---|---|'
        foreach ($c in $azure.AddressCollisions) {
            & $add ("| `{0}` | {1} | `{2}` | {3} |" -f `
                $c.PlannedCidr, (ConvertTo-LzSafeString $c.VNetName), $c.ExistingCidr, (ConvertTo-LzSafeString $c.SubscriptionId))
        }
        & $add ''
    }

    # ── Inventory ────────────────────────────────────────────────────────────
    & $add '---'
    & $add ''
    & $add '## Inventory'
    & $add ''
    & $add 'Probe outcomes. **Forbidden** means the probe was blocked, which is not the same as finding nothing — an incomplete inventory cannot be treated as an empty one.'
    & $add ''

    foreach ($domainName in @('GitHub', 'Entra', 'Azure', 'Terraform')) {
        $domain = $Discovery.$domainName
        if (-not $domain) { continue }

        & $add "### $domainName"
        & $add ''
        & $add '| Probe | Status | Count | Notes |'
        & $add '|---|---|---|---|'
        foreach ($key in $domain.Probes.Keys) {
            $p = $domain.Probes[$key]
            $icon = switch ($p.Status) {
                'Ok'          { '✅ Ok' }
                'Empty'       { '⚪ None' }
                'Forbidden'   { '🚫 Forbidden' }
                'Unavailable' { '⚠️ Unavailable' }
                'Error'       { '❌ Error' }
            }
            $note = if ($p.Status -in @('Ok', 'Empty')) { '' } else { ConvertTo-LzSafeString $p.Message }
            & $add ("| {0} | {1} | {2} | {3} |" -f (ConvertTo-LzSafeString $key), $icon, $p.Count, $note)
        }
        & $add ''

        $blocked = @($domain.Probes.Values | Where-Object { $_.Status -eq 'Forbidden' })
        if ($blocked.Count -gt 0) {
            & $add "**$($blocked.Count) probe(s) were blocked in this domain.** The inventory above is incomplete. Resolve access before relying on it:"
            & $add ''
            foreach ($b in $blocked) {
                & $add "- **$(ConvertTo-LzSafeString $b.Name)** — $(ConvertTo-LzSafeString $b.Remediation)"
            }
            & $add ''
        }
    }

    # ── GitHub capability detail ─────────────────────────────────────────────
    if ($Discovery.GitHub -and $Discovery.GitHub.Capabilities.Limitations.Count -gt 0) {
        & $add '---'
        & $add ''
        & $add '## GitHub control limitations'
        & $add ''
        & $add 'These controls cannot be applied on the detected account tier. They are named explicitly rather than skipped silently, so the reduced control set is a decision you make rather than one you discover later.'
        & $add ''
        foreach ($l in $Discovery.GitHub.Capabilities.Limitations) { & $add "- $(ConvertTo-LzSafeString $l)" }
        & $add ''
    }

    # ── Next steps ───────────────────────────────────────────────────────────
    & $add '---'
    & $add ''
    & $add '## Next steps'
    & $add ''
    if ($readiness -and $readiness.FailCount -gt 0) {
        & $add '1. Resolve every **Fail** in the remediation section above.'
        & $add '2. Re-run discovery to confirm.'
        & $add '3. Only then run the bootstrap broker.'
    }
    elseif ($readiness -and $readiness.WarningCount -gt 0) {
        & $add '1. Review each **Warning** and decide explicitly whether to accept it.'
        & $add '2. Run the bootstrap broker when you are satisfied.'
    }
    else {
        & $add '1. Run the bootstrap broker.'
    }
    & $add ''
    & $add '```bash'
    & $add 'pwsh ./bootstrap-broker.ps1 -ConfigPath <path-to>/lz-config.json'
    & $add '```'
    & $add ''
    & $add '> The bootstrap broker is not yet implemented — it is stage 9 of the factory build. This report is produced by stage 4 (the discovery engine) and is already usable on its own as a pre-flight assessment.'
    & $add ''

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $Path -Value $sb.ToString() -Encoding utf8
    return $Path
}

function Export-LzDiscoveryInventory {
    <#
    .SYNOPSIS
        Write the machine-readable inventory consumed by later factory stages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Discovery,
        [Parameter(Mandatory)][string]$Path
    )

    $payload = [ordered]@{
        generatedAt    = $Discovery.GeneratedAt
        factoryVersion = $Discovery.FactoryVersion
        durationSeconds = [math]::Round($Discovery.DurationSeconds, 2)
        readOnly       = $true
        readiness      = if ($Discovery.Readiness) {
            [ordered]@{
                ready        = $Discovery.Readiness.Ready
                passCount    = $Discovery.Readiness.PassCount
                warningCount = $Discovery.Readiness.WarningCount
                failCount    = $Discovery.Readiness.FailCount
                checks       = $Discovery.Readiness.Checks
            }
        } else { $null }
        domains        = [ordered]@{}
    }

    foreach ($domainName in @('GitHub', 'Entra', 'Azure', 'Terraform')) {
        $domain = $Discovery.$domainName
        if (-not $domain) { continue }

        $probes = [ordered]@{}
        foreach ($key in $domain.Probes.Keys) {
            $p = $domain.Probes[$key]
            $probes[$key] = [ordered]@{
                status      = $p.Status
                count       = $p.Count
                conclusive  = $p.Conclusive
                message     = (Protect-LzSecretText $p.Message)
                remediation = $p.Remediation
                items       = $p.Items
            }
        }

        $domains = [ordered]@{ probes = $probes }
        if ($domain.PSObject.Properties.Name -contains 'Capabilities') { $domains['capabilities'] = $domain.Capabilities }
        if ($domain.PSObject.Properties.Name -contains 'AddressCollisions') { $domains['addressCollisions'] = $domain.AddressCollisions }
        if ($domain.PSObject.Properties.Name -contains 'ExistingLandingZone') { $domains['existingLandingZone'] = $domain.ExistingLandingZone }

        $payload.domains[$domainName] = $domains
    }

    $json = $payload | ConvertTo-Json -Depth 12
    $json = Protect-LzSecretText $json

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $Path -Value $json -Encoding utf8
    return $Path
}
