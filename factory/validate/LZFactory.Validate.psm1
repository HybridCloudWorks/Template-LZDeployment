#Requires -Version 7.0
<#
    Post-render validation gate.

    Proves a rendered tree is deployable BEFORE the Stage 10 scaffold publishes
    it: inventory integrity, terraform fmt/init/validate, workflow pinning
    policy, provider-constraint consistency, lint, and security scanning. Every
    gate runs even after an earlier gate fails, so validate-report.json always
    shows the complete remediation surface, and the run throws at the end when
    any gate failed.

    Isolation contract: `terraform init -backend=false` writes `.terraform/`
    directories inside whatever tree it runs against, and the scaffold's
    inventory check rejects any file render-manifest.json does not declare. The
    tool-driven gates (V02-V08) therefore run against a scratch copy of the
    rendered tree under the system temp directory, removed in a finally block,
    so the rendered tree stays byte-identical for the scaffold. Only V01 and
    the manifest SHA-256 read the real rendered directory.

    Helper duplication (the inventory check, the required_providers parser) is
    deliberate: phase modules must stay independently usable, so this module
    imports neither the scaffold module nor the factory/ci scripts — the same
    rationale as Test-LzRendererCidrOverlap in
    factory/renderer/public/Test-LzRenderGuards.ps1.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-LzValidateEvent {
    param([string]$Level, [string]$Message)
    $colour = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $colour
}

function Get-LzValidateProperty {
    param([object]$Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Resolve-LzValidatePath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
}

function Invoke-LzValidateTool {
    # Runs an external tool and reports its exit code instead of throwing:
    # a non-zero exit is a gate finding, not an infrastructure failure.
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments,
        [string]$WorkingDirectory
    )
    $oldLocation = Get-Location
    $output = @()
    $exitCode = 1
    try {
        if ($WorkingDirectory) { Set-Location $WorkingDirectory }
        $output = @(& $Command @Arguments 2>&1 | ForEach-Object { "$_" })
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output += "$($_.Exception.Message)"
        $exitCode = 1
    }
    finally {
        Set-Location $oldLocation
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Write-LzValidateGateLog {
    # Factory CI log naming: lowercased, non-alphanumerics collapsed to '-'.
    param(
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][string]$GateName,
        [AllowEmptyCollection()][string[]]$Lines
    )
    $logName = ($GateName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') + '.log'
    @($Lines) | Set-Content (Join-Path $LogDirectory $logName) -Encoding utf8
    return $logName
}

function New-LzValidateGateRecord {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'skipped')][string]$Status,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [AllowEmptyCollection()][string[]]$Details = @(),
        [string]$Remediation = '',
        [string]$Log = ''
    )
    return [pscustomobject]@{
        id = $Id
        name = $Name
        status = $Status
        durationSeconds = [math]::Round(((Get-Date) - $StartedAt).TotalSeconds, 3)
        details = @($Details)
        remediation = $Remediation
        log = $Log
    }
}

function Test-LzValidateInventory {
    <#
        V01 core: the rendered tree must be exactly what render-manifest.json
        declares — no missing files, no extras, no rooted/traversal/duplicate
        destinations. Independent lightweight re-implementation of the check
        the scaffold performs, kept here so the validate phase never imports
        the scaffold module. Content problems are returned as findings (the
        gate loop must keep running); only I/O catastrophes throw.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RenderedDirectory)

    $root = Resolve-LzValidatePath $RenderedDirectory
    $details = [Collections.Generic.List[string]]::new()
    $manifest = $null
    $manifestSha256 = $null

    $manifestPath = Join-Path $root 'render-manifest.json'
    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        $details.Add("render-manifest.json not found in $root.")
    }
    else {
        # Same file hash the scaffold's Get-LzScaffoldInventory computes: the
        # scaffold compares report.manifestSha256 against it to reject stale
        # validation evidence for a different render.
        $manifestSha256 = (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json -Depth 30 }
        catch { $details.Add("render-manifest.json is not valid JSON: $($_.Exception.Message)") }
    }

    if ($manifest) {
        $filesProperty = Get-LzValidateProperty $manifest 'files'
        if ($null -eq $filesProperty) {
            $details.Add('render-manifest.json does not contain a files inventory.')
        }
        else {
            $expected = @()
            foreach ($file in @($filesProperty)) {
                $destination = "$(Get-LzValidateProperty $file 'Destination')" -replace '\\', '/'
                if ([string]::IsNullOrWhiteSpace($destination) -or
                    [IO.Path]::IsPathRooted($destination) -or
                    $destination -match '(^|/)\.\.(/|$)') {
                    $details.Add("Unsafe renderer destination: '$destination'.")
                    continue
                }
                $expected += $destination.TrimStart('/')
            }
            foreach ($duplicate in @($expected | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)) {
                $details.Add("Duplicate manifest destination: $duplicate")
            }
            $actual = @(Get-ChildItem $root -Recurse -File -Force | ForEach-Object {
                $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
            } | Where-Object { $_ -ne 'render-manifest.json' } | Sort-Object)
            $expectedSorted = @($expected | Sort-Object -Unique)
            foreach ($path in @($expectedSorted | Where-Object { $_ -notin $actual })) {
                $details.Add("Manifest file missing on disk: $path")
            }
            foreach ($path in @($actual | Where-Object { $_ -notin $expectedSorted })) {
                $details.Add("Unexpected file not declared by render-manifest.json: $path")
            }
        }
    }

    return [pscustomobject]@{
        Status = if ($details.Count -eq 0) { 'pass' } else { 'fail' }
        Details = @($details)
        Manifest = $manifest
        ManifestSha256 = $manifestSha256
    }
}

function Get-LzValidateWorkflowPinFindings {
    <#
        V05 core: every `uses:` reference in the rendered workflow tree must be
        pinned to a full 40-hex commit SHA. Local composite actions (./...) and
        docker:// references are exempt — the same exemptions as
        factory/ci/Test-ActionPins.ps1. A generated repository whose supply
        chain is unpinned is a compliance regression against the factory's own
        action-pinning policy.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $findings = @()
    $workflowRoot = Join-Path $Root '.github/workflows'
    if (-not (Test-Path $workflowRoot -PathType Container)) { return @() }
    foreach ($file in @(Get-ChildItem $workflowRoot -Recurse -File -Include *.yml, *.yaml)) {
        $relativePath = $file.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
        $lineNumber = 0
        foreach ($line in @(Get-Content $file.FullName)) {
            $lineNumber++
            # Unlike Test-ActionPins.ps1's matcher this also accepts the inline
            # list form ('- uses:'); this repo's workflows put uses: on its own
            # line, but a rendered corpus must not evade the gate by style.
            if ($line -notmatch '^\s*-?\s*uses:\s*(?<reference>[^\s#]+)') { continue }
            $reference = $Matches.reference
            if ($reference.StartsWith('./') -or $reference.StartsWith('docker://')) { continue }
            if ($reference -notmatch '^[^@]+@[0-9a-fA-F]{40}$') {
                $findings += "${relativePath}:${lineNumber}: '$reference' is not pinned to a full 40-hex commit SHA."
            }
        }
    }
    return @($findings)
}

function Get-LzValidateProviderDeclaration {
    # Parses the `required_providers` blocks of one .tf file into records of
    # {Name, Source, Version, Line}. Duplicated (simplified) from
    # factory/ci/Test-ProviderConstraints.ps1 rather than shared, so the
    # validate phase stays independently usable — and unlike that script this
    # gate compares the rendered tree only against ITSELF, not a canonical
    # registry: it exists to catch the defect class where two rendered files
    # declare the same provider with mutually exclusive constraints, which
    # fails at `terraform init` in the customer repository.
    param([Parameter(Mandatory)][string]$Path)

    $declarations = @()
    $inRequiredProviders = $false
    $requiredProvidersDepth = 0
    $currentName = $null
    $currentSource = $null
    $currentVersion = $null
    $currentLine = 0
    $lineNumber = 0

    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        $lineNumber++
        $text = ($line -replace '#.*$', '')

        if (-not $inRequiredProviders) {
            if ($text -match '^\s*required_providers\s*\{') {
                $inRequiredProviders = $true
                $requiredProvidersDepth = 1
            }
            continue
        }

        if ($null -eq $currentName) {
            if ($text -match '^\s*(?<name>[A-Za-z_][A-Za-z0-9_-]*)\s*=\s*\{') {
                $currentName = $Matches.name
                $currentSource = $null
                $currentVersion = $null
                $currentLine = $lineNumber
                continue
            }
            $requiredProvidersDepth += ([regex]::Matches($text, '\{')).Count
            $requiredProvidersDepth -= ([regex]::Matches($text, '\}')).Count
            if ($requiredProvidersDepth -le 0) { $inRequiredProviders = $false }
            continue
        }

        if ($text -match '^\s*source\s*=\s*"(?<value>[^"]+)"') { $currentSource = $Matches.value }
        if ($text -match '^\s*version\s*=\s*"(?<value>[^"]+)"') { $currentVersion = $Matches.value }

        if ($text -match '\}') {
            $declarations += [pscustomobject]@{
                Name    = $currentName
                Source  = $currentSource
                Version = $currentVersion
                Line    = $currentLine
            }
            $currentName = $null
        }
    }

    return $declarations
}

function Get-LzValidateProviderConstraintFindings {
    <#
        V06 core: across all rendered *.tf files, a provider source declared
        with two different version-constraint strings anywhere in the tree is
        a finding. Comparison is exact string equality between the tree's own
        declarations — divergent spelling is exactly the drift that produces
        "does not match configured version constraint" at terraform init.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $rootFull = Resolve-LzValidatePath $Root
    $declarations = @()
    foreach ($file in @(Get-ChildItem $rootFull -Recurse -File -Filter '*.tf')) {
        $relativePath = $file.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
        foreach ($declaration in @(Get-LzValidateProviderDeclaration -Path $file.FullName)) {
            if ([string]::IsNullOrWhiteSpace($declaration.Source) -or
                [string]::IsNullOrWhiteSpace($declaration.Version)) { continue }
            $declarations += [pscustomobject]@{
                Source  = $declaration.Source
                Version = $declaration.Version
                File    = $relativePath
                Line    = $declaration.Line
            }
        }
    }

    $findings = @()
    foreach ($group in @($declarations | Group-Object Source)) {
        $constraints = @($group.Group | ForEach-Object Version | Sort-Object -Unique)
        if ($constraints.Count -gt 1) {
            $sites = (@($group.Group | ForEach-Object { "$($_.File):$($_.Line) '$($_.Version)'" }) -join '; ')
            $findings += "Provider $($group.Name) is declared with $($constraints.Count) different version constraints ($($constraints -join ' | ')) - mutually exclusive constraints fail at terraform init in the customer repository. Declarations: $sites"
        }
    }
    return @($findings)
}

function Invoke-LzValidate {
    <#
    .SYNOPSIS
        Run the post-render validation gates against a rendered tree.
    .DESCRIPTION
        Runs gates V01-V08, writes per-gate logs and validate-report.json under
        the evidence directory, and throws when any gate failed. The rendered
        tree itself is never modified: tool-driven gates run against a scratch
        copy (see the module header for the isolation contract).
    .PARAMETER RenderedDirectory
        The renderer output tree containing render-manifest.json.
    .PARAMETER EvidenceDirectory
        Where validate-report.json and logs/ are written.
    .PARAMETER Strict
        Treat a missing optional tool (tflint; checkov/tfsec/trivy) as a gate
        failure instead of a recorded skip.
    .PARAMETER SkipSecurityScan
        Record an explicit operator skip for the security-scan gate.
    .PARAMETER SkipLint
        Record an explicit operator skip for the lint gate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RenderedDirectory,
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [switch]$Strict,
        [switch]$SkipSecurityScan,
        [switch]$SkipLint
    )

    $started = Get-Date
    if (-not (Test-Path $RenderedDirectory -PathType Container)) {
        throw "Rendered directory not found: $RenderedDirectory. Run the render phase (Invoke-LzRender) first, or set LZ_RENDERED_PATH."
    }
    $renderedRoot = Resolve-LzValidatePath $RenderedDirectory
    New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
    $evidenceRoot = Resolve-LzValidatePath $EvidenceDirectory
    $logDirectory = Join-Path $evidenceRoot 'logs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

    Write-LzValidateEvent INFO "Post-render validation gate: $renderedRoot"
    $gates = [Collections.Generic.List[object]]::new()
    $terraform = Get-Command terraform -ErrorAction SilentlyContinue
    $terraformRemediation = 'Install terraform per the factory-version.json toolchain contract (terraform >= 1.9.0) and re-run ./validate-render.ps1.'

    # ── V01 inventory-integrity (reads the REAL rendered tree) ───────────────
    $gateStarted = Get-Date
    $inventory = Test-LzValidateInventory -RenderedDirectory $renderedRoot
    $v01Lines = if ($inventory.Status -eq 'pass') { @('Rendered tree matches render-manifest.json exactly.') } else { $inventory.Details }
    $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V01 inventory-integrity' -Lines $v01Lines
    $gates.Add((New-LzValidateGateRecord -Id 'V01' -Name 'inventory-integrity' -Status $inventory.Status `
        -StartedAt $gateStarted -Details $inventory.Details `
        -Remediation 'Re-run the render phase rather than hand-editing the rendered tree; the scaffold refuses any tree that differs from render-manifest.json.' -Log $log))

    # ── V02-V08 run against a scratch copy so terraform init's .terraform/
    #    directories never land in the rendered tree the scaffold inventories.
    $scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ('lz-validate-' + [guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -Path $renderedRoot -Destination $scratchRoot -Recurse -Force

        # ── V02 format-verification ──────────────────────────────────────────
        $gateStarted = Get-Date
        if (-not $terraform) {
            $details = @('terraform was not found on PATH; formatting cannot be verified. This gate fails closed.')
            $status = 'fail'
        }
        else {
            $result = Invoke-LzValidateTool terraform @('fmt', '-check', '-recursive', '-diff') $scratchRoot
            $status = if ($result.ExitCode -eq 0) { 'pass' } else { 'fail' }
            $details = if ($result.ExitCode -eq 0) { @('terraform fmt -check found no formatting drift.') } else { $result.Output }
        }
        $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V02 format-verification' -Lines $details
        $gates.Add((New-LzValidateGateRecord -Id 'V02' -Name 'format-verification' -Status $status `
            -StartedAt $gateStarted -Details $details `
            -Remediation "Re-run the render phase with terraform on PATH (the renderer formats its output), or fix the offending templates; the generated repository fails its own fmt check otherwise. $terraformRemediation" -Log $log))

        $terraformDirectories = @(Get-ChildItem $scratchRoot -Recurse -File -Filter '*.tf' |
            ForEach-Object DirectoryName | Sort-Object -Unique)

        # ── V03 dependency-integrity ─────────────────────────────────────────
        # `terraform init -backend=false` in every *.tf directory is what
        # proves all module sources and provider constraints are resolvable.
        $gateStarted = Get-Date
        $v03Lines = [Collections.Generic.List[string]]::new()
        $v03Failures = @()
        if (-not $terraform) {
            $v03Lines.Add('terraform was not found on PATH; dependency resolution cannot be verified. This gate fails closed.')
            $status = 'fail'
        }
        else {
            foreach ($directory in $terraformDirectories) {
                $display = $directory.Substring($scratchRoot.Length).TrimStart('\', '/') -replace '\\', '/'
                if (-not $display) { $display = '.' }
                $result = Invoke-LzValidateTool terraform @('init', '-backend=false', '-input=false', '-no-color') $directory
                $v03Lines.Add("== terraform init $display (exit $($result.ExitCode)) ==")
                foreach ($line in $result.Output) { $v03Lines.Add($line) }
                if ($result.ExitCode -ne 0) { $v03Failures += $display }
            }
            $status = if ($v03Failures.Count -eq 0) { 'pass' } else { 'fail' }
        }
        $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V03 dependency-integrity' -Lines $v03Lines
        $details = if ($status -eq 'pass') {
            @("terraform init -backend=false succeeded in $($terraformDirectories.Count) director(ies).")
        }
        elseif ($v03Failures.Count -gt 0) {
            @("terraform init failed in: $($v03Failures -join ', '). See the gate log for the full output.")
        }
        else { @($v03Lines) }
        $gates.Add((New-LzValidateGateRecord -Id 'V03' -Name 'dependency-integrity' -Status $status `
            -StartedAt $gateStarted -Details $details `
            -Remediation "Fix the unresolvable module source or provider constraint in the template corpus and re-render; every rendered directory must pass terraform init -backend=false. $terraformRemediation" -Log $log))

        # ── V04 terraform-validate ───────────────────────────────────────────
        $gateStarted = Get-Date
        $v04Lines = [Collections.Generic.List[string]]::new()
        $v04Failures = @()
        if (-not $terraform) {
            $v04Lines.Add('terraform was not found on PATH; configuration validity cannot be verified. This gate fails closed.')
            $status = 'fail'
        }
        else {
            foreach ($directory in $terraformDirectories) {
                $display = $directory.Substring($scratchRoot.Length).TrimStart('\', '/') -replace '\\', '/'
                if (-not $display) { $display = '.' }
                # A shared module that declares configuration_aliases takes its
                # aliased provider from the CALLER's providers map, so Terraform
                # cannot validate it standalone (hashicorp/terraform#28490
                # class). Init still ran in V03; validate is recorded as an
                # explicit per-directory skip, matching Invoke-FactoryCI.
                $aliasDeclarations = @(Get-ChildItem $directory -File -Filter '*.tf' |
                    Select-String -Pattern 'configuration_aliases' -SimpleMatch -List)
                if ($aliasDeclarations.Count -gt 0) {
                    $v04Lines.Add("== terraform validate $display SKIPPED: shared module declares configuration_aliases and requires caller-injected aliased providers; standalone terraform validate is impossible upstream ==")
                    continue
                }
                $result = Invoke-LzValidateTool terraform @('validate', '-no-color') $directory
                $v04Lines.Add("== terraform validate $display (exit $($result.ExitCode)) ==")
                foreach ($line in $result.Output) { $v04Lines.Add($line) }
                if ($result.ExitCode -ne 0) { $v04Failures += $display }
            }
            $status = if ($v04Failures.Count -eq 0) { 'pass' } else { 'fail' }
        }
        $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V04 terraform-validate' -Lines $v04Lines
        $details = if ($status -eq 'pass' -and $terraform) {
            @("terraform validate succeeded (configuration_aliases directories recorded as explicit skips - see the gate log).")
        }
        elseif ($v04Failures.Count -gt 0) {
            @("terraform validate failed in: $($v04Failures -join ', '). See the gate log for the full output.")
        }
        else { @($v04Lines) }
        $gates.Add((New-LzValidateGateRecord -Id 'V04' -Name 'terraform-validate' -Status $status `
            -StartedAt $gateStarted -Details $details `
            -Remediation "Fix the invalid HCL in the template corpus and re-render. $terraformRemediation" -Log $log))

        # ── V05 workflow-pinning-policy ──────────────────────────────────────
        $gateStarted = Get-Date
        $pinFindings = @(Get-LzValidateWorkflowPinFindings -Root $scratchRoot)
        $status = if ($pinFindings.Count -eq 0) { 'pass' } else { 'fail' }
        $details = if ($status -eq 'pass') { @('Every rendered workflow uses: reference is SHA-pinned (./local and docker:// exempt).') } else { $pinFindings }
        $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V05 workflow-pinning-policy' -Lines $details
        $gates.Add((New-LzValidateGateRecord -Id 'V05' -Name 'workflow-pinning-policy' -Status $status `
            -StartedAt $gateStarted -Details $details `
            -Remediation 'Pin the action to its full commit SHA in the workflow template (see factory/ci/Test-ActionPins.ps1 for the canonical registry) and re-render.' -Log $log))

        # ── V06 provider-constraint-integrity ────────────────────────────────
        $gateStarted = Get-Date
        $constraintFindings = @(Get-LzValidateProviderConstraintFindings -Root $scratchRoot)
        $status = if ($constraintFindings.Count -eq 0) { 'pass' } else { 'fail' }
        $details = if ($status -eq 'pass') { @('Every provider is declared with one consistent version constraint across the rendered tree.') } else { $constraintFindings }
        $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V06 provider-constraint-integrity' -Lines $details
        $gates.Add((New-LzValidateGateRecord -Id 'V06' -Name 'provider-constraint-integrity' -Status $status `
            -StartedAt $gateStarted -Details $details `
            -Remediation 'Align every declaration of the provider on one constraint string in the template corpus and re-render.' -Log $log))

        # The rendered Terraform content lives under terraform/ in a generated
        # repository; fall back to the tree root for non-standard layouts.
        $terraformRoot = if (Test-Path (Join-Path $scratchRoot 'terraform') -PathType Container) {
            Join-Path $scratchRoot 'terraform'
        } else { $scratchRoot }

        # ── V07 lint (tflint) ────────────────────────────────────────────────
        $gateStarted = Get-Date
        $tflint = Get-Command tflint -ErrorAction SilentlyContinue
        if ($SkipLint) {
            $status = 'skipped'
            $details = @('Operator skip requested (-SkipLint / LZ_VALIDATE_SKIP_LINT=true).')
            $remediation = 'Remove the skip and re-run; operator skips require a documented owner-approved exception.'
        }
        elseif (-not $tflint) {
            if ($Strict) {
                $status = 'fail'
                $details = @('tflint was not found on PATH and -Strict is set: a missing optional tool is a failure, not a skip.')
                $remediation = 'Install tflint and re-run ./validate-render.ps1, or drop -Strict / LZ_VALIDATE_STRICT only with an approved exception.'
            }
            else {
                $status = 'skipped'
                $details = @('tflint was not found on PATH.')
                $remediation = 'WARN: install tflint to enable lint gating.'
            }
        }
        else {
            $result = Invoke-LzValidateTool tflint @('--recursive', '--no-color') $terraformRoot
            $status = if ($result.ExitCode -eq 0) { 'pass' } else { 'fail' }
            $details = if ($result.ExitCode -eq 0) { @('tflint --recursive reported no findings.') } else { $result.Output }
            $remediation = 'Fix the lint findings in the template corpus and re-render.'
        }
        $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V07 lint' -Lines $details
        $gates.Add((New-LzValidateGateRecord -Id 'V07' -Name 'lint' -Status $status `
            -StartedAt $gateStarted -Details $details -Remediation $remediation -Log $log))

        # ── V08 security-scan ────────────────────────────────────────────────
        $gateStarted = Get-Date
        # PINNED TO CHECKOV (TODO item 2.15). This used to take the first of
        # checkov/tfsec/trivy found on PATH, which made the gate's verdict
        # depend on what the runner happened to have installed: the 2026-08-06
        # strict run used tfsec and recorded ONE low finding, while checkov on
        # the same corpus reports forty. A gate whose answer changes with the
        # toolbox is not a gate. tfsec is also archived upstream, folded into
        # Trivy, so checkov is the one with a future.
        #
        # Accepted findings are suppressed at the resource with
        # `#checkov:skip=<id>:<reason>` so the exception sits next to the code it
        # excuses rather than in a config file nobody opens.
        $scanners = @(
            [pscustomobject]@{ Name = 'checkov'; Arguments = @('-d', $terraformRoot, '--quiet', '--compact') }
        )
        $scanner = @($scanners | Where-Object { Get-Command $_.Name -ErrorAction SilentlyContinue }) | Select-Object -First 1
        if ($SkipSecurityScan) {
            $status = 'skipped'
            $details = @('Operator skip requested (-SkipSecurityScan / LZ_VALIDATE_SKIP_SECURITY_SCAN=true).')
            $remediation = 'Remove the skip and re-run; operator skips require a documented owner-approved exception.'
        }
        elseif (-not $scanner) {
            if ($Strict) {
                $status = 'fail'
                $details = @('No security scanner (checkov, tfsec, trivy) was found on PATH and -Strict is set: a missing optional tool is a failure, not a skip.')
                $remediation = 'Install checkov, tfsec, or trivy and re-run ./validate-render.ps1, or drop -Strict / LZ_VALIDATE_STRICT only with an approved exception.'
            }
            else {
                $status = 'skipped'
                $details = @('No security scanner (checkov, tfsec, trivy) was found on PATH.')
                $remediation = 'WARN: install checkov, tfsec, or trivy to enable security-scan gating.'
            }
        }
        else {
            $result = Invoke-LzValidateTool $scanner.Name $scanner.Arguments $scratchRoot
            $status = if ($result.ExitCode -eq 0) { 'pass' } else { 'fail' }
            $details = if ($result.ExitCode -eq 0) { @("$($scanner.Name) reported no findings.") } else { $result.Output }
            $remediation = "Resolve the $($scanner.Name) findings in the template corpus and re-render; see the gate log."
        }
        $log = Write-LzValidateGateLog -LogDirectory $logDirectory -GateName 'V08 security-scan' -Lines $details
        $gates.Add((New-LzValidateGateRecord -Id 'V08' -Name 'security-scan' -Status $status `
            -StartedAt $gateStarted -Details $details -Remediation $remediation -Log $log))
    }
    finally {
        if (Test-Path $scratchRoot) {
            Remove-Item $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($gate in $gates) {
        switch ($gate.status) {
            'pass' { Write-LzValidateEvent OK "$($gate.id) $($gate.name)" }
            'skipped' { Write-LzValidateEvent WARN "$($gate.id) $($gate.name) skipped: $(@($gate.details) -join ' ') $($gate.remediation)" }
            'fail' { Write-LzValidateEvent FAIL "$($gate.id) $($gate.name): $((@($gate.details) | Select-Object -First 3) -join ' ') Remediation: $($gate.remediation)" }
        }
    }

    $failedGates = @($gates | Where-Object status -eq 'fail')
    $manifest = $inventory.Manifest
    $report = [ordered]@{
        schemaVersion = '1.0.0'
        generatedAt = $started.ToUniversalTime().ToString('o')
        factoryVersion = "$(Get-LzValidateProperty $manifest 'factoryVersion' 'unknown')"
        configSchemaVersion = "$(Get-LzValidateProperty $manifest 'schemaVersion' 'unknown')"
        company = "$(Get-LzValidateProperty $manifest 'company' 'unknown')"
        renderedDirectory = $renderedRoot
        manifestSha256 = $inventory.ManifestSha256
        strict = [bool]$Strict
        overallStatus = if ($failedGates.Count -eq 0) { 'pass' } else { 'fail' }
        gateCount = $gates.Count
        passedCount = @($gates | Where-Object status -eq 'pass').Count
        failedCount = $failedGates.Count
        skippedCount = @($gates | Where-Object status -eq 'skipped').Count
        durationSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
        gates = @($gates)
    }
    $reportPath = Join-Path $evidenceRoot 'validate-report.json'
    $report | ConvertTo-Json -Depth 20 | Set-Content $reportPath -Encoding utf8

    if ($failedGates.Count -gt 0) {
        Write-LzValidateEvent FAIL "Validation report: $reportPath"
        throw "Validation failed: gate(s) $((@($failedGates | ForEach-Object id)) -join ', ') failed. See $reportPath and the per-gate logs under $logDirectory for remediation. The rendered tree must not be scaffolded until every gate passes."
    }
    Write-LzValidateEvent OK "All validation gates passed ($($report.passedCount) passed, $($report.skippedCount) skipped): $reportPath"
    return [pscustomobject]@{
        Report = [pscustomobject]$report
        ReportPath = $reportPath
        LogDirectory = $logDirectory
    }
}

Export-ModuleMember -Function @(
    'Invoke-LzValidate'
    'Test-LzValidateInventory'
    'Get-LzValidateWorkflowPinFindings'
    'Get-LzValidateProviderConstraintFindings'
)
