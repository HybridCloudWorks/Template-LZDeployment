# TODO — HCW Landing Zone Factory

> **File contract (operator-defined 2026-08-07, supersedes the 2026-08-06
> contract).** This file holds **ALL action items found repo-wide**, triaged in
> chronological, logical order, **in phases**, so it can serve as a proper
> handoff. Items blocked on the operator or an external system appear here too
> — each names its gate and references its **[REVIEW.md](REVIEW.md)** entry,
> the blocker registry that records who can unblock it and the next concrete
> action. Completed work is recorded in [CHANGELOG.md](CHANGELOG.md)
> (new-features changelog). Root markdown is limited to four files: README.md,
> CHANGELOG.md, REVIEW.md, TODO.md.

**Last Updated**: August 7, 2026
**Status**: 🟢 Phase 1 closed (PR #77); every open item is gated as stated
per item
**Operator activities & stage checklists**: [docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)
**External tracking**: [GitHub Issues](https://github.com/HybridCloudWorks/Template-LZDeployment/issues)

---

## What this repo is

The **Landing Zone Factory** (see [README.md](README.md)): a disposable
installer that renders a self-contained, per-customer landing-zone repository
from `lz-config.json` (`site/` wizard → discovery → broker → render →
validate → scaffold). The client runs it once, on their own machine, and the
copy is deleted; the **generated** repository is the deliverable
([decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)).
The legacy self-deploying path (`terraform/live/` + numbered workflows) is
retained as the Stage 13 dogfood instance.

---

## Phase 1 — Startable engineering fixes

**Closed 2026-08-07 (PR #77)** — all three items (1.1 template-corpus
V07/V08 cleanup, 1.2 Linux scaffold hidden-file crash, 1.3 enum/`contains`
drift-checker gap) shipped, including the live-tree mirror of the 1.1
cleanup. The record is in [CHANGELOG.md](CHANGELOG.md). Two notes survive
the closure:

- Item 1.1's validation criterion — `validate-render.ps1 -Strict` passing
  V07/V08 with **no skips recorded** — is not yet confirmed: tflint/tfsec
  were unavailable in the sandbox. The confirmation run is folded into
  item 3.1.
- Item 1.3 was partially stale when picked up: the production checker gap
  had already been closed by 435845e (#69, 2026-08-05) after the item was
  written (2026-08-02), and the 2026-08-06 consolidation missed it — the
  deliverable became the missing end-to-end proof. When work lands, close
  the TODO item in the same change.

The next startable work is gated: see Phases 2–5.

---

## Phase 2 — Implementation gated on operator ratifications

Implementation is straightforward once the named decision is ratified. The
decision itself — who can make it and what has to be chosen — is recorded in
the referenced REVIEW.md entry; do not start the work before the gate lifts.

### 2.1 Implement the resource-provider registration strategy (decision 0006) — CLOSED

Closed 2026-08-07: the gate lifted when the operator ratified
[decision 0006](docs/decisions/0006-resource-provider-registration.md)
in-session (Option A broker-time registration + Option B's PF-D preflight
finding; Option C ratified against). Shipped: broker registration step with
bounded polling and per-subscription per-namespace audit entries, read-only
PF-D findings, the Factory CI "Resource provider coverage" corpus↔broker
drift check, and explicit `resource_provider_registrations = "none"` in the
rendered (and mirrored live) provider blocks. **Criterion split**: the
`Test-Bootstrap.ps1`-green criterion is verified (85/0); the "first apply
into a fresh subscription no longer fails" criterion is estate-gated and
folds into item 3.1's authenticated-toolchain run, the same way item 1.1's
strict-validation residual did. Item number retained so cross-references
stay stable; record in [CHANGELOG.md](CHANGELOG.md).

### 2.2 Disposition of `scripts/Initialize-ClientFork.ps1` — CLOSED

Closed 2026-08-07: the gate lifted when the operator ratified
[decision 0007](docs/decisions/0007-retire-client-copy-hardening.md)
in-session (retire the hardening stages; keep `-CreatePrivateCopy` as the
documented private-copy mechanic; retargeting at the generated repo ruled
out — the broker is the sole hardening owner there). Shipped: the script
stripped to the private-copy mechanic with visibility read-back, its
comment-based help rewritten to the surviving purpose, the retired
parameters (`-Branch`, `-RequiredApprovals`, `-RequiredChecks`,
`-EnforceAdmins`) removed, and every live instruction that pointed at the
hardening stages updated (README, CLAUDE.md, USER-CHECKLIST, REVIEW.md §2,
the Stage 13 runbook's Gate 2/Gate 5/troubleshooting rows, the
engagement-lifecycle runbook). Both validation criteria verified:
`grep -rn Initialize-ClientFork` shows no stale live instructions
(decision-record and CHANGELOG history retained as history), and
`Get-Help` parses the rewritten help cleanly. Item number retained so
cross-references stay stable; record in [CHANGELOG.md](CHANGELOG.md).

### 2.3 Wire `nsg-flow-logs` into a live stack

Module exists with secure defaults; zero `terraform/live/*` callers, so no
NSG flow logs are collected anywhere.
**Owner**: `terraform-module-engineer`.
**Gate**: operator choice of NSG set + Log Analytics workspace (cost and
data-residency posture) — [REVIEW.md](REVIEW.md) §11, now with the options
paper it needs:
[decision 0009 (Proposed)](docs/decisions/0009-nsg-flow-log-scope-and-workspace-target.md)
costs the three coupled choices (NSG scope, workspace target, hosting stack)
and recommends A2 + B1 + C2 behind a default-off `enable_nsg_flow_logs`.
**Still open** — the gate lifts on operator ratification, not on the paper
existing. The paper also names the module outputs and corpus↔live parity work
the wiring implies.
**Validation**: `terraform validate` in the touched stack; plan shows the
flow-log resources against the chosen NSGs only.

### 2.4 Implement `keyvault-cmk` and `sentinel-siem`

Both are `check "module_not_implemented"` scaffolds, render-blocked (guards
G02/G03) — a **decided deferral**, not drift.
**Owner**: `azure-platform-architect` (design) → `terraform-module-engineer`.
**Gate**: operator re-opens the deferral — [REVIEW.md](REVIEW.md) §14 lists
the design inputs required (key hierarchy, vault scope, connectors,
retention split).
**Validation**: modules render, `terraform validate` passes, wizard labels
updated from scaffold-only.

### 2.5 Wire `Configure-DeploymentOptions.ps1` output into Terraform

`.azure/deployment-options.yaml` is a planning-only artifact; no layer reads
it. Two of the three modules it would gate are the item-2.4 scaffolds.
**Owner**: `alz-orchestrator` (cross-domain: script, renderer, layers).
**Gate**: item 2.4 ships first — [REVIEW.md](REVIEW.md) §16.
**Validation**: enabling an option in the YAML changes the corresponding plan.

### 2.6 Record the generated-repo ownership policy

Mechanism is settled (`github.ownershipModel`/`ownerName` are required schema
fields); what is open is engagement policy — which owner value CBTS uses and
whether repos are transferred to the client afterward. Watch schema risk GH1
(`personal` on a Free plan silently loses protected environments).
**Owner**: operator decides; `docs-knowledge-curator` records.
**Gate**: [REVIEW.md](REVIEW.md) §13.
**Validation**: policy recorded in a decision record; wizard/docs reference it.

### 2.7 Update dot-folder contract text to the 2026-08-07 file contract — CLOSED

Closed 2026-08-07 (PR #77): the gate lifted when the operator approved the
dot-folder edits in-session. `docs-knowledge-curator.md`'s "What lives where"
now states the four-file root contract and the `docs/USER-CHECKLIST.md`
location; the `020-rbac-validation.yml` comment cites REVIEW.md §1. The
validation grep for "PROD-TODO" returns no live-instruction references.
Item number retained so cross-references stay stable; record in
[CHANGELOG.md](CHANGELOG.md).

---

## Phase 3 — Authenticated-toolchain execution

Needs a provisioned toolchain with real `az`/`gh` sessions (or the named
external access); no Azure estate mutation implied.

### 3.1 Execute the Stage 9/10/11 suites and the engagement-wrapped validation gate

The **standalone** validation gate is done (executed 2026-08-06 — record in
[REVIEW.md](REVIEW.md) §7). What remains: the broker/import/scaffold-apply
suites against authenticated `az`/`gh`, and the validate phase inside the full
engagement wrapper (discovery → broker → render → validate → scaffold,
`scripts/Invoke-CustomerEngagement.ps1`) with real discovery artifacts.
Carried forward from item 1.1 (closed 2026-08-07 with this criterion unmet):
the strict run must confirm V07/V08 pass with real tflint/tfsec and **no
skips recorded** — the corpus cleanup shipped, but the tools were unavailable
in the sandbox, so the skip-free pass is unproven.
Carried forward from item 2.1 (closed 2026-08-07): confirm against a real
estate that a broker apply registers the decision-0006 namespaces (audit
entries `registered`/`already-registered`, none left `pending`) and that the
first apply into a fresh subscription no longer fails
`MissingSubscriptionRegistration` — the code path is test-covered, but the
end-to-end proof needs authenticated `az` and a fresh subscription.
**Owner**: `alz-orchestrator` (multi-stage execution).
**Gate**: provisioned, authenticated toolchain — [REVIEW.md](REVIEW.md) §7.
**Validation**: suite runs recorded with plan/audit evidence files; wrapper
completes plan-first end to end; `validate-render.ps1 -Strict` against a
fresh render passes V07/V08 with no skips recorded.

### 3.2 Publish the prepared wiki review edits

The 2026-08-06 content review of the 11 migrated wiki docs is complete;
verdicts and the ready-to-apply patch live in
[docs/wiki-review/](docs/wiki-review/README.md). Only the push is blocked.
**Owner**: `docs-knowledge-curator`.
**Gate**: wiki write access — [REVIEW.md](REVIEW.md) §15 (commands in the
review README).
**Validation**: the 11 wiki pages carry the HISTORICAL banner; `Home.md`
labels corrected.

---

## Phase 4 — Go-live chain

**Deferred, not pending** — the operator has not opened the go-live phase
([REVIEW.md](REVIEW.md) §§1–9 banner). Chronological order within the chain:

### 4.1 Confirm the engagement tenant and create the live identity estate

No landing-zone identity estate exists; every PR fails `azure/login`. The
reachable tenant is a regulated-industry client's — creating identities there
without engagement-owner confirmation is prohibited.
**Owner**: operator confirms tenant; `github-actions-engineer` supports the
bootstrap run. **Gate**: [REVIEW.md](REVIEW.md) §1.
**Validation**: `azure-auth-test.yml` token exchange green from a real PR.

### 4.2 Enable required status checks on upstream `main` (+ settings read-back)

`main` has no `required_status_checks` (six dependabot PRs merged red
2026-08-02). Upstream factory repo only — client copies are never hardened
(decision 0004). Includes the settings not checkable from a clone (secret
scanning, required approvals).
**Owner**: `github-actions-engineer`. **Gate**: repository administration —
[REVIEW.md](REVIEW.md) §2 (single-owner approval caveat noted there).
**Validation**: GitHub API read-back shows the required contexts enforced.

### 4.3 Set GitHub Pages source to "GitHub Actions"

One-time repo setting; `deploy-pages.yml` is ready.
**Owner**: operator (Settings → Pages). **Gate**: [REVIEW.md](REVIEW.md) §8.
**Validation**: published site serves `site/` at root, `frontend/` under
`/frontend/`.

### 4.4 Supply `-SandboxSubscriptionId` at bootstrap (per engagement)

Without it, platform-management's sandbox-cleanup Contributor assignment fails
`AuthorizationFailed`. Only blocks sandbox-enabled engagements.
**Owner**: operator input per engagement. **Gate**: [REVIEW.md](REVIEW.md) §6.
**Validation**: broker plan shows the sandbox RBAC assignment scoped to the
real subscription.

### 4.5 Verify the pipeline runs green end to end

No recorded successful run of `010-terraform-init.yml`,
`020-rbac-validation.yml`, `terraform-plan.yml`, `terraform-apply.yml`.
**Owner**: `deployment-troubleshooter` if anything stays red after 4.1.
**Gate**: item 4.1 — [REVIEW.md](REVIEW.md) §3.
**Validation**: successful runs of all four workflows on a real PR/push.

### 4.6 Resolve the backend duality / TFC migration (Issue #11)

HCP Terraform is the recorded default; `terraform/live/*` is azurerm; the
bootloader and workflow 010 assume TFC.
**Owner**: `github-actions-engineer`. **Gate**: interactive TFC
org/workspace/token setup — [REVIEW.md](REVIEW.md) §9,
[Issue #11](https://github.com/HybridCloudWorks/Template-LZDeployment/issues/11).
**Validation**: one backend per stack, init green against it.

### 4.7 Execute and accept the Stage 13 dogfood instance

`factory-version.json` carries `dogfoodInstanceAppliesGreen = false`.
Gate-by-gate runbook:
[docs/runbooks/stage13-dogfood-execution.md](docs/runbooks/stage13-dogfood-execution.md);
acceptance criteria: [docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md) Stage 13.
**Owner**: operator executes; `alz-orchestrator` sequences support.
**Gate**: items 4.1–4.5 — [REVIEW.md](REVIEW.md) §4.
**Validation**: every rendered layer applies green; read-back evidence
accepted; `dogfoodInstanceAppliesGreen=true` set in a separately reviewed PR.

---

## Phase 5 — Release-time items

### 5.1 Run Stage 14 release attestation and the release-gate PR

Until v1.0.0 gates pass, every customer deployment is formally a verification
exercise (factory v0.9.0, `oidcTokenExchangeVerifiedLive = false`).
**Owner**: operator; `github-actions-engineer` supports.
**Gate**: item 4.7 — [REVIEW.md](REVIEW.md) §5.
**Validation**: `release-readiness-report.json` with `readyForPromotion=true`;
separate reviewed release-gate PR.

### 5.2 Review module-README cost estimates against current Azure pricing

The variable tables are machine-enforced (`factory/ci/Test-ModuleDocs.ps1`);
the cost figures are not derivable from HCL and go stale against Azure list
prices.
**Owner**: `azure-cost-governance` prepares; a human accepts the figures.
**Gate**: release cadence — [REVIEW.md](REVIEW.md) §17 (cannot be automated).
**Validation**: reviewed figures dated in each module README.

### 5.3 Bump `factory-version.json` in lock-step

Bumping the version forces the wizard `FACTORY_VERSION` constant, four test
fixtures, and the Stage 14 v0.9.0 evidence-selection instructions
([docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)) to move together — an
operator-record change (CHANGELOG, 2026-08-06).
**Owner**: `github-actions-engineer`.
**Gate**: item 5.1 promotion decision.
**Validation**: `node factory/tests/test.js` and
`pwsh -File factory/tests/Test-Renderer.ps1` green after the bump.

---

## Key documents

- **[REVIEW.md](REVIEW.md)** — blocker registry: who can unblock each gated
  item above, and the next concrete action
- **[CHANGELOG.md](CHANGELOG.md)** — record of shipped work
- **[docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)** — per-stage operator
  activities (moved from the root 2026-08-07; the renderer separately emits a
  per-customer copy into generated repos)
- **[docs/decisions/](docs/decisions/)** — decision records;
  **[docs/runbooks/](docs/runbooks/)** — operator procedures;
  **[docs/wiki-review/](docs/wiki-review/README.md)** — wiki review evidence
- **[GitHub wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki)** — operator guidebook and historical source material

---

**Owner**: Platform Engineering
