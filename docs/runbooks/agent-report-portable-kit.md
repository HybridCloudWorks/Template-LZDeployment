# Capability usage report — portable kit

End-of-task usage reporting for any Claude Code project. At the end of each task,
the assistant prints a short table of *why* each capability was used; a `Stop` hook
then parses the session transcript and prints the authoritative *counts*. Reasons
come from the assistant, numbers come from the transcript — the assistant never
guesses a count, and the hook never invents a reason.

This repo's `.claude/hooks/` directory is the source. Everything below is what you
copy into another repo and how to wire it. Budget about 10 minutes.

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
