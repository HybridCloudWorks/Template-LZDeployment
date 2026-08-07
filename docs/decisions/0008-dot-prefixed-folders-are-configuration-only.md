# Decision 0008 — Dot-prefixed folders are configuration-only; documentation migrates out

- **Status**: Accepted — operator-directed 2026-08-07
- **Date**: 2026-08-07
- **Deciders**: operator (directed 2026-08-07); `docs-knowledge-curator`
  (implemented)
- **Technical depth**: L200 (design)

## Context and Problem Statement

Dot-prefixed folders (`.github/`, `.claude/`, `.azure/`, …) exist because a
tool requires them: workflows, agent definitions, linter configuration,
platform-required files. They are configuration locations, not documentation
repositories — but documentation had accreted in `.claude/`: the cross-domain
contracts register, a portable-kit how-to for the reporting hook, and an
orchestration inventory that partially duplicated CLAUDE.md's rules (a
multiple-sources-of-truth hazard). The four-file root contract
(operator-defined 2026-08-07: README.md, CHANGELOG.md, REVIEW.md, TODO.md)
and the `docs/` tree already define where documentation belongs; markdown
hiding in dot-folders escapes both that contract and routine doc review.

## Considered Options

1. **Configuration-only policy with content-based classification** — markdown
   found in a dot-folder is classified by its *content* (not filename): tool
   configuration stays; documentation is validated, migrated to its
   authoritative destination (the four root files, `docs/`, or the GitHub
   wiki), references retargeted, and the source deleted.
2. **Status quo** — leave documentation where a tool's folder happens to hold
   it. Rejected: dot-folders are invisible to doc review, the `.claude/README.md`
   duplication had already produced two sources of truth for routing and
   guardrail rules, and the root/docs contracts cannot govern files they do
   not cover.
3. **Allowlist individual files** — keep a per-file exception list. Rejected:
   the exception list is itself documentation-about-configuration that would
   drift; content classification needs no registry.

## Decision

Chosen option: **configuration-only policy with content-based
classification**, because tool-required locations should contain exactly what
the tool reads, and everything humans read belongs where the repo's
documentation contracts govern it.

**Classification rulings** (2026-08-07 audit of every dot-folder):

- **Configuration, allowed in place**: `.github/` (CODEOWNERS, dependabot,
  workflows, CodeQL — no markdown at all), `.azure/`
  (`deployment-options.yaml.example`), `.claude/agents/*.md` (10),
  `.claude/commands/*.md` (3), `.claude/skills/**/*.md` (94 skills),
  `.claude/hooks/agent-report.ps1`, `.claude/settings.json`,
  `.claude/agent-report.json`. The agent/command/skill markdown is
  tool-required: Claude Code loads these files from these locations.
  `factory/tests/.out/**` is untracked generated output — no finding.
- **Documentation, migrated**: the three findings below.

**Findings and disposition** (this table is the policy's consolidation
report):

| Finding | Content classification | Destination | Disposition |
| --- | --- | --- | --- |
| `.claude/CROSS-DOMAIN-CONTRACTS.md` | Architecture documentation — register of 7 load-bearing multi-file contracts | `docs/CROSS-DOMAIN-CONTRACTS.md` | `git mv`, content intact; its two decision-record links rebased; all referrers retargeted (10 agent files, `lz-plan` command, CLAUDE.md, README.md, `frontend/README.md` + `frontend/app.js`, 4 module READMEs incl. factory template twins, `scripts/Add-PlanFederatedCredential.ps1`, Stage 13 runbook, decision 0003, `factory/templates/.github/workflows/terraform-plan.yml.tmpl`, `factory/bootstrap/LZFactory.Bootstrap.psm1`) |
| `.claude/hooks/README.md` | How-to guide — portable kit for the usage-report hook | `docs/runbooks/agent-report-portable-kit.md` | `git mv`; technical content intact (validated against CLAUDE.md §§2–4); prose now names `.claude/hooks/` as the source explicitly; links rebased |
| `.claude/README.md` | Orchestration inventory + import provenance, partially duplicating CLAUDE.md §§1/2/5 rules | `docs/claude-orchestration.md` | Unique content migrated (directory layout, agents/commands/skills tables, import provenance, MCP notes, hook summary); duplicated rule prose trimmed to links — CLAUDE.md stays the sole source for routing/reporting/guardrail rules; source deleted |

`.claude/` needs no README of its own: Claude Code loads nothing from
`.claude/README.md` — only humans read it, and humans are served by
CLAUDE.md's opening pointer to the inventory page.

## Consequences

- **Positive**: dot-folders contain exactly what tools read; documentation is
  governed by the four-file root contract and `docs/` review; the
  routing/reporting/guardrail rules have a single source of truth (CLAUDE.md)
  for the first time since the `.claude/README.md` duplication.
- **Negative**: agents and scripts referencing the contracts register carry
  the longer `docs/` path; CHANGELOG history still names the old paths
  (history is immutable — those entries are correct about the past and are
  not retargeted).
- **Follow-ups**: future markdown discovered in any dot-folder is a finding —
  classify content, migrate to `docs/`, the four root files, or the wiki (the
  wiki once write access exists — REVIEW.md §15), verify referrers, delete
  the source. No open items remain from the 2026-08-07 audit.
