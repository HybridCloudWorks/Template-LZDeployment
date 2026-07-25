# Claude Code orchestration for HCW-Plan_LZDeployment

Source-controlled agents, skills, slash commands, and tool configuration for this
repository. Everything here loads automatically when Claude Code opens the repo —
there is nothing to install.

```
.claude/
├── agents/      10 orchestration agents (routing + domain specialists)
├── commands/    3 slash commands
├── skills/      94 skills, flat namespace
├── settings.json
└── README.md
.mcp.json        Azure + Microsoft Learn MCP servers (repo root)
```

## Agents

`alz-orchestrator` is the entry point for anything spanning more than one domain.
It reads `TODO.md` and `docs/` first, decomposes the request, and delegates.

| Agent | Owns | Typical trigger |
| --- | --- | --- |
| `alz-orchestrator` | Cross-domain routing and sequencing | "stand up the landing zone", "review the whole pipeline" |
| `azure-platform-architect` | Azure design — topology, SKUs, identity, readiness | "how should this be built on Azure" |
| `terraform-module-engineer` | `terraform/modules/`, `terraform/live/`, tests, imports | "refactor this module", "add a spoke" |
| `github-actions-engineer` | `.github/workflows/`, OIDC, pinning, PR gates | "fix this workflow", "add a check" |
| `azure-cost-governance` | Cost, quotas, Azure Policy, compliance audits | "what will this cost", "check quotas" |
| `deployment-troubleshooter` | Root-causing failed runs, applies, auth, drift | "the deploy failed" |
| `ansible-automation-engineer` | Guest-OS config management, runbook conversion | "turn this script into automation" |
| `frontend-experience-designer` | `site/` factory configuration wizard, visual design, UX | "improve the options page" |
| `docs-knowledge-curator` | `docs/`, `README.md`, `CHANGELOG.md`, `TODO.md` | "document what we just did" |
| `lz-change-reviewer` | Read-only pre-merge review (no edit tools) | before opening or merging a PR |

## Commands

| Command | Does |
| --- | --- |
| `/lz-plan <change>` | Full plan across design → Terraform → pipeline → cost → docs |
| `/lz-review [scope]` | Read-only pre-merge review of the current branch |
| `/lz-diagnose <error>` | Root-cause a failing run, apply, or auth error |

## Skills

94 skills in a flat namespace under `skills/`. Cross-references between skills in
the same pack are preserved.

| Pack | Count | Skills |
| --- | --- | --- |
| **Azure** (`microsoft/azure-skills`) | 26 | `airunway-aks-setup`, `appinsights-instrumentation`, `azure-ai`, `azure-aigateway`, `azure-cloud-migrate`, `azure-compliance`, `azure-compute`, `azure-cost`, `azure-deploy`, `azure-diagnostics`, `azure-enterprise-infra-planner`, `azure-kubernetes`, `azure-kusto`, `azure-messaging`, `azure-prepare`, `azure-quotas`, `azure-reliability`, `azure-resource-lookup`, `azure-resource-visualizer`, `azure-storage`, `azure-upgrade`, `azure-validate`, `entra-agent-id`, `entra-app-registration`, `microsoft-foundry`, `python-appservice-deploy` |
| **Terraform / Packer** (`hashicorp/agent-skills`) | 17 | `aws-ami-builder`, `azure-image-builder`, `azure-verified-modules`, `new-terraform-provider`, `provider-actions`, `provider-docs`, `provider-resources`, `provider-test-patterns`, `push-to-registry`, `refactor-module`, `run-acceptance-tests`, `terraform-policy`, `terraform-search-import`, `terraform-stacks`, `terraform-style-guide`, `terraform-test`, `windows-builder` |
| **GitHub Agentic Workflows** (`github/gh-aw`) | 40 | `agentic-workflows`, `awf-release-integrator`, `checkout-credential-review`, `console-rendering`, `copilot-review`, `create-canvas`, `custom-agents`, `debugging-workflows`, `developer`, `documentation`, `error-messages`, `error-pattern-safety`, `gh-agent-session`, `gh-agent-task`, `github-copilot-agent-tips-and-tricks`, `github-discussion-query`, `github-issue-query`, `github-labels-query`, `github-mcp-server`, `github-pr-query`, `github-script`, `github-workflows-query`, `go-codemod`, `go-linters`, `http-mcp-headers`, `javascript-refactoring`, `jqschema`, `messages`, `optimize-agentic-workflow`, `otel-queries`, `playwright-cli`, `pr-finisher`, `pr-to-go-linter`, `prompt-token-efficiency`, `reporting`, `sergo-examples`, `ssl-skill-normalizer`, `temporary-id-safe-output`, `workflow-step-summaries` |
| **Ansible** (`matteoveglia/ansible-skills-codex`) | 7 | `ansible-collections`, `ansible-convert`, `ansible-debug`, `ansible-interactive`, `ansible-lint`, `ansible-playbook`, `ansible-vault` |
| **Notion** | 4 | `notion-knowledge-capture`, `notion-meeting-intelligence`, `notion-research-documentation`, `notion-spec-to-implementation` |
| **UI/UX** (`anthropics/skills`) | 1 | `frontend-design` |

### Changes made during import

- Each pack shipped its skills two to four times (`skills/`, `.agents/skills/`,
  and for Azure also `apm_modules/**` and `.github/plugins/**`). Only the canonical
  `skills/` copy was imported.
- `http_mcp_headers` → `http-mcp-headers`, with the frontmatter `name` and every
  in-pack cross-reference updated. Skill names may not contain underscores.
- Dropped: `.DS_Store`, `__MACOSX/`, Windows `.lnk` shortcuts, `.url` bookmarks,
  `plugin.json`, and `skills-lock.json` (provenance is recorded in this table).
- **Not imported:** the Azure pack's `hooks/` telemetry scripts
  (`track-telemetry.ps1` / `.sh`), which post usage data to Microsoft on every
  `PostToolUse`. Enable them deliberately if you want that; they were left out
  rather than silently turned on for everyone who clones this repo.

## Tools

`.mcp.json` at the repo root declares two MCP servers:

- **`azure`** — `@azure/mcp` via `npx`. Backs the Azure skills' live subscription
  queries (resource lookup, cost, quotas, diagnostics). Uses your existing `az`
  login. Requires Node.js.
- **`microsoft-learn`** — remote HTTP server for grounding Azure claims in current
  Microsoft Learn documentation instead of model recall.

The four `notion-*` skills additionally need Notion's MCP server; it is not
declared here because it requires a personal credential. Connect it yourself if
you use those skills.

## Capability usage report

`hooks/agent-report.ps1` is registered in `settings.json` as a **`Stop`** hook. It
is currently **enabled** (`agent-report.json` → `"enabled": true`). When disabled it
exits silently; when enabled it parses the session transcript, counts actual
`tool_use` records (agents by `subagent_type`, skills by `skill`, everything else
as a tool) since the previous report, and prints the tally. It never blocks a turn.

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/agent-report.ps1 -Mode Toggle -State On
```

This is local-only — nothing is transmitted anywhere, unlike the Azure pack's
telemetry hooks below, which remain unimported. Routing and reporting rules live in
[`../CLAUDE.md`](../CLAUDE.md).

## Guardrails

`settings.json` allowlists routine read-only commands (`git status`,
`terraform validate`, `az account show`, `gh run view`, …) and **denies** the
operations that can destroy this landing zone: `terraform apply`, `destroy`,
`state rm/mv`, `force-unlock`, `import`, `az` resource deletion,
`gh workflow run`, `gh pr merge`, and force-pushing or pushing to `main`.

Every agent definition repeats the same rule: produce the plan or the change, then
stop. Applying it is the operator's call.
