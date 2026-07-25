<#
.SYNOPSIS
    Post-task capability usage report for this repository.

.DESCRIPTION
    Two modes:

      -Mode Toggle -State On|Off
          Persists the on/off setting to .claude/agent-report.json.
          (A string rather than a bool: pwsh -File cannot bind $true/$false.)

      -Mode Report   (default; wired as a Claude Code `Stop` hook)
          Reads the hook payload from stdin, parses the session transcript, and
          counts actual tool_use blocks recorded there. Emits a report as a
          hook `systemMessage`. Exits 0 always — this hook never blocks a turn.

    Counting is derived from the transcript JSONL, not estimated. Agent, Skill
    and every other tool call is counted by name. Only the segment since the
    previous report is counted; the offset is kept per session under
    .claude/.agent-report-state/.

.NOTES
    Windows PowerShell 5.1 and PowerShell 7+ compatible.
#>
[CmdletBinding()]
param(
    [ValidateSet('Report', 'Toggle')]
    [string]$Mode = 'Report',

    [ValidateSet('On', 'Off')]
    [string]$State,

    # Explicit transcript path; normally supplied via the stdin hook payload.
    [string]$TranscriptPath,

    [string]$SessionId
)

$ErrorActionPreference = 'Stop'

$claudeDir  = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $claudeDir 'agent-report.json'
$stateDir   = Join-Path $claudeDir '.agent-report-state'

function Get-ReportConfig {
    if (-not (Test-Path -LiteralPath $configPath)) {
        return [pscustomobject]@{ enabled = $false }
    }
    try {
        Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    } catch {
        [pscustomobject]@{ enabled = $false }
    }
}

if ($Mode -eq 'Toggle') {
    if (-not $State) { throw "-State On|Off is required when -Mode Toggle." }
    $Enabled = ($State -eq 'On')
    $payload = [ordered]@{
        '$comment' = "Toggle for the post-task capability usage report. Flip with 'turn on agent report' / 'turn off agent report', or edit this file directly. Read by .claude/hooks/agent-report.ps1 (Stop hook)."
        enabled    = [bool]$Enabled
    }
    ($payload | ConvertTo-Json -Depth 3) + "`n" |
        Set-Content -LiteralPath $configPath -Encoding UTF8 -NoNewline
    Write-Output "agent report: $(if ($Enabled) { 'ON' } else { 'OFF' }) (persisted to .claude/agent-report.json)"
    exit 0
}

# ---------------------------------------------------------------- Report mode

# The Stop hook payload arrives on stdin as a single JSON object.
$stdin = ''
if (-not [Console]::IsInputRedirected) {
    $stdin = ''
} else {
    $stdin = [Console]::In.ReadToEnd()
}

if ($stdin.Trim()) {
    try {
        $hookInput     = $stdin | ConvertFrom-Json
        if (-not $TranscriptPath) { $TranscriptPath = $hookInput.transcript_path }
        if (-not $SessionId)      { $SessionId      = $hookInput.session_id }
    } catch {
        # Malformed payload: fall through to the parameter values, if any.
    }
}

$config = Get-ReportConfig
if (-not $config.enabled) { exit 0 }

if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath)) {
    $msg = 'Capability usage report: exact usage telemetry is not available from the current context (no readable session transcript).'
    (@{ systemMessage = $msg } | ConvertTo-Json -Compress)
    exit 0
}

if (-not (Test-Path -LiteralPath $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}
if (-not $SessionId) { $SessionId = 'unknown-session' }
$safeId    = ($SessionId -replace '[^A-Za-z0-9_.-]', '_')
$statePath = Join-Path $stateDir "$safeId.offset"

$startLine = 0
if (Test-Path -LiteralPath $statePath) {
    $raw = (Get-Content -LiteralPath $statePath -Raw).Trim()
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed)) { $startLine = $parsed }
}

$lines = @(Get-Content -LiteralPath $TranscriptPath)
if ($startLine -gt $lines.Count) { $startLine = 0 }   # transcript rotated
$segment = if ($startLine -lt $lines.Count) { $lines[$startLine..($lines.Count - 1)] } else { @() }

$agents = @{}   # subagent_type -> count
$skills = @{}   # skill name    -> count
$tools  = @{}   # tool name     -> count

foreach ($line in $segment) {
    if (-not $line.Trim()) { continue }
    try { $entry = $line | ConvertFrom-Json } catch { continue }

    $content = $entry.message.content
    if (-not $content) { continue }

    foreach ($block in @($content)) {
        if ($block.type -ne 'tool_use') { continue }
        switch ($block.name) {
            'Agent' {
                $key = if ($block.input.subagent_type) { $block.input.subagent_type } else { 'general-purpose' }
                $agents[$key] = 1 + [int]$agents[$key]
            }
            'Skill' {
                $key = if ($block.input.skill) { $block.input.skill } else { '(unnamed)' }
                $skills[$key] = 1 + [int]$skills[$key]
            }
            default {
                $tools[$block.name] = 1 + [int]$tools[$block.name]
            }
        }
    }
}

"$($lines.Count)" | Set-Content -LiteralPath $statePath -Encoding ASCII -NoNewline

function Format-Section {
    param([string]$Label, [hashtable]$Map)
    if ($Map.Count -eq 0) { return "$Label used: None" }
    $items = $Map.GetEnumerator() | Sort-Object -Property @{ Expression = 'Value'; Descending = $true }, Name |
        ForEach-Object { "  - $($_.Name) x$($_.Value)" }
    (@("$Label used:") + $items) -join "`n"
}

$distinctAgents = $agents.Count
$distinctSkills = $skills.Count
$distinctTools  = $tools.Count
$callAgents = ($agents.Values | Measure-Object -Sum).Sum; if (-not $callAgents) { $callAgents = 0 }
$callSkills = ($skills.Values | Measure-Object -Sum).Sum; if (-not $callSkills) { $callSkills = 0 }
$callTools  = ($tools.Values  | Measure-Object -Sum).Sum; if (-not $callTools)  { $callTools  = 0 }

$report = @(
    '--- Capability Usage Report (from session transcript) ---'
    (Format-Section -Label 'Agents' -Map $agents)
    (Format-Section -Label 'Skills' -Map $skills)
    (Format-Section -Label 'Tools'  -Map $tools)
    'Counts (distinct / total calls):'
    "  - Agents: $distinctAgents / $callAgents"
    "  - Skills: $distinctSkills / $callSkills"
    "  - Tools:  $distinctTools / $callTools"
    'Counts are observed tool_use records since the last report. Reasons are supplied by the assistant, not by this hook.'
) -join "`n"

(@{ systemMessage = $report } | ConvertTo-Json -Compress)
exit 0
