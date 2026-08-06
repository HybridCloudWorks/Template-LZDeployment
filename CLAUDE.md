# Assistant operating instructions — HCW-Plan_LZDeployment

This repository ships its own agents, skills, slash commands, and MCP servers under
`.claude/` and `.mcp.json`. See [.claude/README.md](.claude/README.md) for the full
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
- `scripts/Initialize-ClientFork.ps1` hardens the *disposable* copy — the wrong
  target under this model. Do not lead with it.
- The real first step of a client run is toolchain + authentication + confirming
  the target tenant, then the `site/` wizard.

Full record and open questions:
[docs/decisions/0004-factory-copy-is-a-disposable-installer.md](docs/decisions/0004-factory-copy-is-a-disposable-installer.md).

## 1. Semantic capability matching

Route on **intent**, not on keywords. A request never has to contain the words
"agent", "skill", or "tool", and the user never has to ask for delegation. Before
starting non-trivial work, decide what the request is actually about and check the
capability inventory for a match.

**How to match**

- Read the request for its *domain* and *verb*: what artifact is being touched, and
  what is being done to it. Map that to the owners table below.
- Treat synonyms, paraphrases, error text, pasted logs, and file paths as routing
  signals. "the pipeline is red", "run 1234 failed", a pasted `terraform plan`
  error, and "why didn't my change deploy" are all the same intent
  (→ `deployment-troubleshooter`), and none of them name a capability.
- A path in the request is strong evidence: `terraform/**` →
  `terraform-module-engineer`; `.github/workflows/**` → `github-actions-engineer`;
  `site/**` → `frontend-experience-designer`; `docs/`, `README.md`,
  `CHANGELOG.md`, `TODO.md` → `docs-knowledge-curator`.
- Prefer an **existing, more specific** capability over a general one, and prefer a
  repo-local capability (`.claude/agents/`, `.claude/commands/`) over a generic
  built-in.
- If the work spans two or more domains, or the next step is unclear, that itself is
  the signal for `alz-orchestrator`.
- **State the choice in one line** when you invoke something: what you picked and
  why it beat the runner-up. Example: "Using `terraform-module-engineer` — this is
  HCL authoring in `terraform/modules/`, not an Azure design decision, so not
  `azure-platform-architect`."
- If nothing in the inventory is a genuine fit, **say so explicitly** ("no repo
  capability applied") and do the work directly. Do not force a match, and do not
  invoke a capability merely to have one to report.

**Domain owners** (full descriptions in each `.claude/agents/*.md` frontmatter)

| Intent, however phrased | Capability |
| --- | --- |
| Cross-domain, sequencing, "where do we start", whole-lifecycle | `alz-orchestrator` |
| Azure design: topology, subscriptions/MGs, networking, identity, SKU sizing | `azure-platform-architect` |
| Authoring/refactoring HCL, modules, `.tftest.hcl`, state imports, plan reading | `terraform-module-engineer` |
| Workflow YAML, OIDC, action pinning, PR gates, `gh` queries, bootstrap script | `github-actions-engineer` |
| Spend, budgets, forecasts, quota/capacity, Azure Policy, compliance audit | `azure-cost-governance` |
| Something is broken and the cause is unknown — red run, apply error, auth, drift | `deployment-troubleshooter` |
| Guest-OS configuration, playbooks/roles, converting scripts to automation | `ansible-automation-engineer` |
| The `site/` factory wizard — UX, layout, validation, and config export | `frontend-experience-designer` |
| Recording what happened: docs, changelog, decision records, task breakdown | `docs-knowledge-curator` |
| Read-only pre-merge review of a branch or PR | `lz-change-reviewer` |

Skills follow the same rule: match the skill's `description` to the request's
intent. `terraform-style-guide`, `terraform-test`, `azure-verified-modules`,
`azure-cost`, `azure-quotas`, `azure-diagnostics`, `ansible-lint`, and
`github-*-query` are the ones this repo's work hits most often.

**Constraint that outranks all of the above:** the session may carry a standing
instruction not to spawn subagents unless asked. Where that applies, do the work
inline and route only to *skills* and *tools*; note the constraint rather than
silently skipping the match.

**Dispatch-by-default** (operator decision, 2026-08-01)

- Dispatch is the standing policy, not an option to weigh. Non-trivial
  single-domain work goes to the domain specialist; anything spanning two or more
  domains goes through `alz-orchestrator`. "Already having context inline" is not
  a reason to skip dispatch. Inline work is reserved for trivial edits and
  `.claude/` meta-config (which has no owner).
- Dispatch briefs must warm-start the specialist: include the task's current
  state, relevant contract references
  ([.claude/CROSS-DOMAIN-CONTRACTS.md](.claude/CROSS-DOMAIN-CONTRACTS.md)), file paths,
  and the validation commands to run. The specialist must not re-discover session
  state from scratch.
- Cross-domain contract changes (see
  [.claude/CROSS-DOMAIN-CONTRACTS.md](.claude/CROSS-DOMAIN-CONTRACTS.md)) are exactly
  the `alz-orchestrator` trigger — never split a contract across
  independently-briefed specialists.

## 2. Capability usage report

Reporting is **enabled in the current repository state**. The setting lives in
[`.claude/agent-report.json`](.claude/agent-report.json) (`{"enabled": true}`).

When it is on, end each completed task with a **reasons table** — no numbers:

```
## Usage Report for This Task
| Capability | Type | Why it was used |
| --- | --- | --- |
| <name> | Agent | <one-line reason> |
| <name> | Skill | <one-line reason> |
| <name> | Tool  | <one-line reason> |

Counts: printed below by the Stop hook, observed per-name from the session
transcript. If no tally appears, telemetry was unavailable this turn.
```

(If nothing was invoked, replace the table with one line: `No repo capabilities
used — <reason>`.)

Rules for this report, which override any instinct to produce a tidy answer:

- **Report only what was actually invoked in this task.** Never list a capability
  you considered, recommended, or described but did not call.
- **Reasons are yours, counts are the transcript's.** The narrative report never
  states call counts — not even ones that look derivable. The `Stop` hook (§3)
  counts `tool_use` records in the session transcript and prints the per-name
  tally directly beneath the report; that tally is the single source of numbers.
- Group multiple uses of one capability into a single row with one combined
  reason; the hook shows how many times it was called.

## 3. Toggling the report

The phrases **"turn on agent report"** and **"turn off agent report"** — and clear
paraphrases such as "enable the usage report", "stop showing the capability
report" — are commands to flip the persisted setting. Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/agent-report.ps1 -Mode Toggle -State On
```

(`-State Off` to turn it off.) This rewrites `.claude/agent-report.json`; the
setting persists across sessions because it is a committed file. It is not in the
`settings.json` allowlist, so the first run each session prompts for permission.
Editing the JSON by hand is equivalent. Confirm the new state back to the user.

## 4. Completion mechanism

`.claude/settings.json` registers a **`Stop` hook** →
`.claude/hooks/agent-report.ps1 -Mode Report`. `Stop` is Claude Code's
end-of-response lifecycle event; this is the only automated completion mechanism in
this repo — there is no webhook, middleware, or CI-side reporter, and none should be
claimed.

The hook:

- reads the hook payload (`transcript_path`, `session_id`) from stdin;
- exits silently (code 0) when `agent-report.json` has `enabled: false`;
- parses the transcript JSONL and counts `tool_use` blocks by name, classifying
  `Agent` calls by `subagent_type`, `Skill` calls by `skill`, and everything else
  as a tool;
- counts only the segment since the previous report, tracked per session under
  `.claude/.agent-report-state/`;
- emits the tally as a hook `systemMessage`, and **never blocks a turn** — no
  `decision: block`, always exit 0.

If the transcript is unreadable it says exactly: "Exact usage telemetry is not
available from the current context."

## 5. Repo guardrails (unchanged)

`settings.json` denies `terraform apply`/`destroy`/`state rm|mv`/`force-unlock`/
`import`, `az` resource deletion, `gh workflow run`, `gh pr merge`, and force-push
or push to `main`. Produce the plan or the change, then stop — applying it is the
operator's call.
