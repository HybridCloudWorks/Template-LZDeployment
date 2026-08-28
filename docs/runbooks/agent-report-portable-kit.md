# Capability usage report — portable kit

End-of-task usage reporting for any Claude Code project. At the end of each task,
the assistant prints a short table of *why* each capability was used; a `Stop` hook
then parses the session transcript and prints the authoritative *counts*. Reasons
come from the assistant, numbers come from the transcript — the assistant never
guesses a count, and the hook never invents a reason.

> **Note, 2026-08-27**: this repo's `.claude/hooks/` directory **no longer
> exists** — the agent-report hook, the agents, and the skills were removed
> when orchestration config moved to the operator's workspace
> ([decision 0021](../decisions/0021-orchestration-config-moves-to-workspace.md)).
> The kit is still usable: the hook script is reproduced in full below, so
> nothing here depends on the deleted directory. Only the sentence "copy it
> from this repo" stopped being true — copy it from this page instead.

Everything below is what you copy into another repo and how to wire it.
Budget about 10 minutes.

## 1. What you get

After each completed task, the combined output looks like this:

```
| Capability | Type | Why it was used |
| --- | --- | --- |
| terraform-module-engineer | Agent | Authored the new module HCL |
| terraform-style-guide | Skill | Conformance pass before commit |
| Read, Edit, Grep | Tool | File inspection and edits |

--- Capability usage counts (observed from session transcript) ---
Agents used:
  - terraform-module-engineer x1
Skills used:
  - terraform-style-guide x1
Tools used:
  - Read x6
  - Edit x3
  - Grep x2
Totals (distinct/calls): Agents 1/1 | Skills 1/1 | Tools 3/11
These are the authoritative numbers for the usage report above; reasons live in that report, counts live here.
```

The table is written by the assistant (per the CLAUDE.md contract in §4). The
block underneath is emitted by the hook as a `systemMessage` — it counts actual
`tool_use` records in the transcript, so it cannot be wrong about numbers.

## 2. Files to copy

| Source (this repo) | Target in your repo | What it is |
| --- | --- | --- |
| `.claude/hooks/agent-report.ps1` | `.claude/hooks/agent-report.ps1` | Dual-mode script: `Report` (the Stop hook) and `Toggle` (flips the setting) |
| `.claude/agent-report.json` | `.claude/agent-report.json` | The on/off toggle: `{"enabled": true}` |

Commit both. The toggle file being committed is the point — the setting survives
across sessions and clones. The script is Windows PowerShell 5.1 and PowerShell 7+
compatible, no modules required.

## 3. Wiring the Stop hook

Merge this into your repo's `.claude/settings.json` — into the existing `"hooks"`
object if you already have one, do not replace the file:

```json
"hooks": {
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/agent-report.ps1\" -Mode Report",
          "timeout": 20
        }
      ]
    }
  ]
}
```

`$CLAUDE_PROJECT_DIR` is supplied by Claude Code at hook time — leave it as-is.
`Stop` fires at the end of every assistant response; Claude Code passes the hook a
JSON payload on stdin containing `transcript_path` and `session_id`, which is all
the script needs.

## 4. CLAUDE.md snippet to paste

Add this to your repo's `CLAUDE.md` (adjust section numbers to your file):

```markdown
## Capability usage report

Reporting is controlled by `.claude/agent-report.json` (`{"enabled": true}`).
When it is on, end each completed task with a reasons-only markdown table:

| Capability | Type | Why it was used |
| --- | --- | --- |
| <name> | Agent / Skill / Tool | <one-line reason> |

Rules, which override any instinct to produce a tidy self-contained answer:

- **Reasons only — never numbers.** Do not state counts, totals, or estimates in
  the table or its prose. The Stop hook prints the authoritative per-name counts
  directly beneath your table, observed from the session transcript. Counts are
  the transcript's; reasons are yours.
- **Report only what was actually invoked in this task.** Never list a capability
  you considered, recommended, or described but did not call.
- **Group repeat uses.** One row per capability (or one row for a set of
  closely-related tools), not one row per call — the hook carries the
  multiplicity.
- If nothing was used, write the single line:
  `No repo capabilities used — <reason>`.

## Toggling the report

The phrases **"turn on agent report"** and **"turn off agent report"** — and
clear paraphrases such as "enable the usage report", "stop showing the capability
report" — are commands to flip the persisted setting. Run:

    powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/agent-report.ps1 -Mode Toggle -State On

(`-State Off` to turn it off.) Editing `.claude/agent-report.json` by hand is
equivalent. Confirm the new state back to the user.

## Completion mechanism

`.claude/settings.json` registers a **`Stop` hook** →
`.claude/hooks/agent-report.ps1 -Mode Report`. This is the only automated
completion mechanism — there is no webhook, middleware, or CI-side reporter, and
none should be claimed. The hook counts only the segment since the previous
report, emits its tally as a hook `systemMessage`, and never blocks a turn
(always exit 0, no `decision: block`). If the transcript is unreadable it says
exactly: "exact usage telemetry is not available from the current context".
```

## 4b. The hook script itself

Reproduced in full so this kit stands alone — the `.claude/hooks/`
directory it used to be copied from was removed from this repository on
2026-08-27 ([decision 0021](../decisions/0021-orchestration-config-moves-to-workspace.md)).
Save as `.claude/hooks/agent-report.ps1` in the target repo.

```powershell
﻿<#
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
        # Stop hooks must never emit unexpected output; Write-Debug is silent
        # unless -Debug/$DebugPreference is set, so this never reaches stdout.
        Write-Debug "agent-report: malformed hook payload on stdin ($($_.Exception.Message))"
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

# ASCII only: this script must render identically under Windows PowerShell 5.1,
# which misreads non-ASCII literals in BOM-less UTF-8 files.
$report = @(
    '--- Capability usage counts (observed from session transcript) ---'
    (Format-Section -Label 'Agents' -Map $agents)
    (Format-Section -Label 'Skills' -Map $skills)
    (Format-Section -Label 'Tools'  -Map $tools)
    "Totals (distinct/calls): Agents $distinctAgents/$callAgents | Skills $distinctSkills/$callSkills | Tools $distinctTools/$callTools"
    'These are the authoritative numbers for the usage report above; reasons live in that report, counts live here.'
) -join "`n"

(@{ systemMessage = $report } | ConvertTo-Json -Compress)
exit 0
```

## 5. Requirements and gotchas

- **The launcher must be on the hook shell's PATH.** On Windows, hook commands
  run under Git Bash (if installed) or PowerShell, and `pwsh` (PowerShell 7) is
  often NOT on that PATH even when installed — `powershell` (5.1, always in
  System32) is the reliable Windows launcher, and the script is 5.1-compatible.
  Verify before trusting it: an unlaunchable hook fails silently (the state
  directory staying empty across sessions is the tell). On macOS/Linux, use
  `pwsh` and install PowerShell, or port the script.
- **Gitignore the state directory.** The hook stores a per-session line offset
  under `.claude/.agent-report-state/` — machine-local noise, never commit it.
  This repo's `.gitignore` already carries the entry
  (`.claude/.agent-report-state/`, last block); add the same line to yours.
- **Per-task tallies, not per-session.** The offset means each report covers only
  the segment since the previous report, so multi-task sessions get a fresh tally
  each time. If the transcript rotated or shrank, the offset resets to 0.
- **Permission prompt on first Toggle.** The Toggle command is not in the
  `settings.json` allowlist, so the first run each session prompts. Editing
  `agent-report.json` by hand is equivalent and avoids the prompt.
- **The 20-second timeout is deliberate.** The hook must never block a turn — it
  always exits 0 and never emits `decision: block`. Keep the timeout; don't
  "harden" the script into something that can fail the turn.
- **Subagent tool calls are not in the parent tally.** Counts come from the
  session transcript, and each subagent has its own transcript. An `Agent` call
  counts as one agent invocation; whatever the subagent did internally is
  invisible here.

## 6. Testing it

Smoke-test with a synthetic transcript — no live session needed. Write a few
JSONL lines with `tool_use` blocks:

```
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"a.tf"}}]}}
{"message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"docs-knowledge-curator","prompt":"x"}}]}}
{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"terraform-style-guide"}}]}}
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"b.tf"}}]}}
```

Save as (say) `smoke.jsonl` and run:

```
powershell -NoProfile -File .claude/hooks/agent-report.ps1 -Mode Report -TranscriptPath smoke.jsonl -SessionId smoke-test
```

Expect exit code 0 and a compact JSON `systemMessage` whose tally reads
`docs-knowledge-curator x1`, `terraform-style-guide x1`, `Read x2`, with
`Totals (distinct/calls): Agents 1/1 · Skills 1/1 · Tools 1/2`. Running it a
second time reports nothing new (the offset advanced). Clean up afterwards:

```
Remove-Item .claude/.agent-report-state/smoke-test.offset
```

## 7. Optional companion patterns

This reporting is the observability half of a larger capability-governance setup.
If you want the rest:

- **Dispatch-by-default policy** — a CLAUDE.md section that routes requests to
  agents/skills on *intent* rather than keywords, so the report has something
  meaningful to count. See §1 of this repo's [CLAUDE.md](../../CLAUDE.md).
- **Cross-domain contracts doc** — a register of multi-file contracts that break
  when edited from one side. See
  [docs/CROSS-DOMAIN-CONTRACTS.md](../CROSS-DOMAIN-CONTRACTS.md).
