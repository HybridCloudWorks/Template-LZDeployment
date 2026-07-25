# Assistant operating instructions — HCW-Plan_LZDeployment

This repository ships its own agents, skills, slash commands, and MCP servers under
`.claude/` and `.mcp.json`. See [.claude/README.md](.claude/README.md) for the full
inventory. This file governs **when** those capabilities get used and **how** usage
is reported.

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

## 2. Capability usage report

Reporting is **enabled in the current repository state**. The setting lives in
[`.claude/agent-report.json`](.claude/agent-report.json) (`{"enabled": true}`).

When it is on, end each completed task with:

```
## Usage Report for This Task
Agents used:
- <name> — <one-line reason>   (or "None")
Skills used:
- <name> — <one-line reason>   (or "None")
Tools used:
- <name> — <one-line reason>   (or "None")
Counts:
- Agents: X
- Skills: X
- Tools: X
```

Rules for this report, which override any instinct to produce a tidy answer:

- **Report only what was actually invoked in this task.** Never list a capability
  you considered, recommended, or described but did not call.
- **Never estimate a count.** If the exact number is not derivable from what you
  can see, write `Unavailable` and the sentence:
  "Exact usage telemetry is not available from the current context."
- The `Stop` hook (§3) independently counts `tool_use` records in the session
  transcript and prints its own tally. If your narrative report disagrees with the
  hook's numbers, the hook's numbers are the observed ones — say so rather than
  reconciling silently.
- The hook counts calls; only you can supply the *reason* for each. Reasons are
  yours, counts are the transcript's.

## 3. Toggling the report

The phrases **"turn on agent report"** and **"turn off agent report"** — and clear
paraphrases such as "enable the usage report", "stop showing the capability
report" — are commands to flip the persisted setting. Run:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/agent-report.ps1 -Mode Toggle -State On
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
