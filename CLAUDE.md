# Assistant operating instructions — HCW-Plan_LZDeployment

This repository ships its own agents, skills, slash commands, and MCP servers under
`.claude/` and `.mcp.json`. See
[docs/claude-orchestration.md](docs/claude-orchestration.md) for the full
inventory. This file governs **when** those capabilities get used and **how** usage
is reported.

## 0. What this repo IS — read before answering any "how do I run this" question

**This repo is a disposable installer. It is not a landing zone, and a client's
copy of it is not an asset anyone governs.**

A client copies this repo to a local machine, runs the tooling once, and deletes
it. The tooling's job is to **create a new, separate repository** and fill it with
the Terraform, OIDC federation, loaders, and workflows for exactly one client's
landing zone. That generated repo is the deliverable and the client's source
control from then on. The factory copy's lifespan is hours.

Consequences that are routinely gotten wrong:

- **Never** open a "first run" answer with hardening the factory copy — branch
  protection, required checks, required approvals, Actions enablement, or
  getting Factory CI green. Those protect long-lived repos. This one is deleted.
  Factory CI is *upstream's* development gate, not part of a client run.
- The **generated** repo is the one that gets hardened, and the broker already
  does it (`factory/bootstrap/LZFactory.Bootstrap.psm1`, ~line 585: branch
  protection, required checks, environments, secrets, plus API read-back).
- `scripts/Initialize-ClientFork.ps1` no longer hardens anything: its hardening
  stages were retired 2026-08-07 for exactly this wrong-target reason
  ([decision 0007](docs/decisions/0007-retire-client-copy-hardening.md)). It
  survives only as the `-CreatePrivateCopy` private-copy mechanic. Still not a
  first step.
- The real first step of a client run is toolchain + authentication + confirming
  the target tenant, then the `site/` wizard.
- **The client runs it, on their own machine** (operator-ratified 2026-08-06),
  so the tenant-confirmation step is load-bearing: it is the client's own `gh`
  and `az` sessions that create the estate.
- **Never assume the copy is a fork.** The operator's position is "forks (or
  clones, whatever is better)" — the motion must work from a plain clone or a
  downloaded archive with no GitHub-side representation at all.

Full record, ratification, and the one remaining open question:
[docs/decisions/0004-factory-copy-is-a-disposable-installer.md](docs/decisions/0004-factory-copy-is-a-disposable-installer.md).

## 1. Orchestration config is workspace-level, not in this repo

**Removed from the repository 2026-08-27** (operator-directed): the agents,
skills, slash commands, and the agent-report `Stop` hook that used to live
under `.claude/` are gone. They are configured at the **operator's workspace
level** and shared across repositories, so keeping a per-repo copy meant
maintaining the same content twice and letting it drift.

What that means in practice:

- **There is no repo-local agent or skill inventory to route to.** Do the work
  inline. If your workspace provides agents or skills, use them under your own
  judgement — this repository neither supplies nor requires any.
- **No usage report, and no `Stop` hook.** The end-of-task capability table and
  the transcript-counting hook that printed its tallies were part of the
  removed set. Do not print a usage report; nothing consumes it.
- **`.claude/settings.json` stays**, because it is not agent-interaction
  config — its deny list is a repository safety control (§5). It no longer
  registers any hook.

**What did NOT change**: §0 above (what this repo is) and §5 below (the
guardrails) are repository facts, independent of how any assistant is
configured. Read both.

Record: [decision 0021](docs/decisions/0021-orchestration-config-moves-to-workspace.md).

## 5. Repo guardrails (unchanged)

[`.claude/settings.json`](.claude/settings.json) denies `terraform apply`/
`destroy`/`state rm|mv`/`force-unlock`/`import`, `az group|resource delete`,
`az deployment * create`, `gh workflow run`, and force-push or push to `main`.
Produce the plan or the change, then stop — applying it is the operator's call.

**Corrected 2026-08-27**: this section previously also listed `gh pr merge` as
denied. It is not — it is in the **allow** list, and always has been. The text
was wrong, not the settings. Merging is permitted; the standing expectation
that you do not merge on your own initiative comes from the sentence above,
not from a deny rule.

Dot-prefixed folders (`.github/`, `.claude/`, `.azure/`, …) hold tooling
configuration only — documentation found there is a finding to migrate to
`docs/`, the four root files, or the wiki
([decision 0008](docs/decisions/0008-dot-prefixed-folders-are-configuration-only.md),
operator-directed 2026-08-07).
