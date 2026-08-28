# Decision 0021 — Claude orchestration config moves to the operator's workspace

- **Status**: **Accepted** — operator-directed 2026-08-27.
- **Date**: 2026-08-27
- **Deciders**: operator (removed the files and set up a workspace-level
  configuration covering all repositories); recorded in-session.
- **Technical depth**: L100 (configuration location; no product behaviour changes)

## Context and Problem Statement

`.claude/` carried 998 tracked files: 10 agents, 982 skill files, 3 slash
commands, the `agent-report.ps1` `Stop` hook, its `agent-report.json` toggle,
and `settings.json`. The same content was being maintained per repository
while the operator works across several, so every repo held a copy that could
drift from the others.

The operator moved this configuration to the **workspace level**, shared
across all repositories, and removed the per-repo copy. Branch
`phase-3-manual-updates` (commit `2f2c8c4`, 2026-08-24) captured that removal
first but was never merged; this record lands the intent deliberately rather
than by merging a commit whose message ("Commit manual updates") did not
explain it.

## Decision

**Agent-interaction configuration leaves the repository. Anything that affects
the repository itself stays.**

Removed (997 files):

| Path | What it was |
| --- | --- |
| `.claude/agents/` | 10 routing and domain-specialist agents |
| `.claude/skills/` | 982 skill files |
| `.claude/commands/` | `lz-diagnose`, `lz-plan`, `lz-review` |
| `.claude/hooks/agent-report.ps1` | `Stop` hook that counted capability usage |
| `.claude/agent-report.json` | on/off toggle for that report |
| `.mcp.json` | MCP server declarations (Azure, Microsoft Learn) — repo root |

`.mcp.json` was removed on the same principle rather than as part of the
original sweep: it declares MCP servers for the assistant and affects nothing
about the repository itself, so it belongs with the workspace configuration.
Anyone who wants those servers declares them at workspace level alongside the
agents and skills.

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
