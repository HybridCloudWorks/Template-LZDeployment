# Decision 0021 — Claude orchestration config moves to the operator's workspace

- **Status**: **Accepted** — operator-directed 2026-08-27.
- **Date**: 2026-08-27
- **Deciders**: operator (removed the files and set up a workspace-level
  configuration covering all repositories); recorded in-session.
- **Technical depth**: L100 (configuration location; no product behaviour changes)

## Context and Problem Statement

`.claude/` **held** 998 tracked files: 10 agents, 982 skill files, 3 slash
commands, the `agent-report.ps1` `Stop` hook, its `agent-report.json` toggle,
and `settings.json`. The same content was being maintained per repository
while the operator works across several, so every repo held a copy that could
drift from the others.

> **Two different 998s — do not conflate them.** `.claude/` *held* 998 files;
> **997** of those were removed (`settings.json` was kept, see below). Adding
> the separate `.mcp.json` removal brings the total *removed* to 998 as well.
> The coincidence is unfortunate but the numbers are right: 998 held − 1 kept
> + 1 root file = 998 removed.

The operator moved this configuration to the **workspace level**, shared
across all repositories, and removed the per-repo copy. Branch
`phase-3-manual-updates` (commit `2f2c8c4`, 2026-08-24) captured that removal
first but was never merged; this record lands the intent deliberately rather
than by merging a commit whose message ("Commit manual updates") did not
explain it.

## Decision

**Agent-interaction configuration leaves the repository. Anything that affects
the repository itself stays.**

Removed in two changes, **998 files total**.

**1. The `.claude/` sweep — 997 files** (PR #111, commit `882caec`):

| Path | Files | What it was |
| --- | ---: | --- |
| `.claude/skills/` | 982 | skill files |
| `.claude/agents/` | 10 | routing and domain-specialist agents |
| `.claude/commands/` | 3 | `lz-diagnose`, `lz-plan`, `lz-review` |
| `.claude/hooks/agent-report.ps1` | 1 | `Stop` hook that counted capability usage |
| `.claude/agent-report.json` | 1 | on/off toggle for that report |
| **Total** | **997** | |

**2. The repo-root MCP declaration — 1 file** (PR #112, commit `9c820b5`):

| Path | Files | What it was |
| --- | ---: | --- |
| `.mcp.json` | 1 | MCP server declarations (Azure, Microsoft Learn) |

`.mcp.json` was removed on the same principle but **not as part of the original
sweep** — it is a separate change, hence the separate count. It declares MCP
servers for the assistant and affects nothing about the repository itself, so
it belongs with the workspace configuration. Anyone who wants those servers
declares them at workspace level alongside the agents and skills.

> **Corrected 2026-08-28** after a Copilot review finding on PR #112. The
> `.mcp.json` row had been appended to a table headed "Removed (997 files)",
> which made the heading wrong and implied the file was part of the 997-file
> sweep. Counts re-derived from the commits themselves
> (`git show --diff-filter=D --name-only`): 997 + 1 = 998.

Kept:

| Path | Why |
| --- | --- |
| `.claude/settings.json` | **Not agent-interaction config.** Its deny list is a repository safety control — it blocks `terraform apply`/`destroy`/`state rm\|mv`/`force-unlock`/`import`, `az` resource deletion, `az deployment * create`, `gh workflow run`, and force-push or push to `main`. Removing it would strip those protections from every clone. Its `hooks` block was dropped, because it registered the deleted hook. |

## Consequences

- **CLAUDE.md §§1–4 were replaced by a single section** stating that
  orchestration config is workspace-level. The old §1 routing table, §2 usage
  report, §3 report toggle, and §4 `Stop`-hook mechanism all described files
  that no longer exist. §0 (what this repo is) and §5 (guardrails) are
  repository facts and are unchanged.
- **No usage report is printed any more.** Nothing consumes it and the hook
  that produced its counts is gone.
- **The guardrails still ship with the repo.** This was the deciding
  consideration for keeping `settings.json`: a fresh clone by anyone else
  still gets the deny list. Workspace-level settings protect the operator's
  own sessions but do not travel with the repository.
- **`docs/claude-orchestration.md` becomes a historical record** rather than a
  live inventory, and `docs/runbooks/agent-report-portable-kit.md` loses its
  in-repo source — both are marked accordingly rather than deleted, since the
  portable kit is still usable by anyone wanting the pattern elsewhere.
- **No product behaviour changes.** Nothing under `factory/`, `scripts/`,
  `site/`, or `.github/workflows/` is affected; the generator emits exactly
  what it emitted before.

## Alternatives considered

- **Remove `settings.json` too**, for a clean sweep of `.claude/`. Rejected:
  the deny list is a repo control, not assistant preference, and dropping it
  silently weakens every clone.
- **Keep the per-repo copy in addition to the workspace one.** Rejected by the
  operator — that is the duplication and drift the move exists to end.
- **Leave the removal only on `phase-3-manual-updates`.** Rejected: an
  unmerged branch is not a decision, and the branch's commit message did not
  record intent, which is why it took a review to establish what it was.
