# Stage 7 Readiness — Workflow Corpus

**Status:** Ready to begin after the decisions in §4 are confirmed  
**Prepared:** 2026-07-25  
**Baseline:** `main` at `d219174`  
**Scope:** Promote the generated-repository workflow corpus. Do not change the
live deployment workflows merely to make the templates resemble them.

## 1. What was reviewed

The Stage 1–6 review covered the accepted factory design and risk register,
schema/version contract, offline wizard, discovery module, renderer and guards,
template manifest, promoted Terraform corpus, all three test suites, the current
ten live workflows, the existing generated `terraform-plan.yml.tmpl`, and the
repo-local Claude orchestration/routing files.

The review was static because this environment has GitHub connector access but no
local checkout or `gh` executable. The handoff records the last full executable
verification: 48 wizard tests, 60 discovery tests, and 100 renderer tests green,
plus two representative rendered trees formatted and validated.

## 2. Confirmed Stage 1–6 baseline

| Stage | Deliverable | Evidence reviewed | Entry state for Stage 7 |
|---|---|---|---|
| 1 | Factory architecture and risk register | `docs/factory/FACTORY-DESIGN.md` | Accepted; status text corrected from “build pending” |
| 2 | Schema and version contract | `factory/schema/lz-config.schema.json`, `factory-version.json` | Schema 1.0.0; factory 0.1.0 |
| 3 | Offline config plane | `site/`, wizard tests | Emits the factory config contract; zero-network invariant remains |
| 4 | Read-only discovery | discovery module, README, 60-test suite | Five-state probe model and BR2 behavior present |
| 5 | Renderer | renderer module, manifest, README, guards, 100-test suite | Fail-closed token engine; G01–G21 implemented |
| 6 | Terraform corpus | manifest and promoted layer/module corpus | Five implemented layers; G21 blocks missing layers |

The existing `factory/templates/.github/workflows/terraform-plan.yml.tmpl` is a
Stage 6 proof of renderer behavior and identity separation. Stage 7 expands the
workflow corpus around it; it does not start from an empty workflow directory.

## 3. Invariants Stage 7 must preserve

1. Workflow-root `permissions: {}`; grant permissions per job.
2. Every external action is pinned to a full commit SHA with a version comment.
3. PR jobs can use only the `*-plan` identity and read-only Azure/state access.
4. Apply jobs authenticate only through `environment:<name>` and the
   corresponding `*-apply` identity.
5. No wildcard OIDC subject and no static Azure client secret.
6. Do not use `pull_request_target` to execute or check out PR-controlled code.
7. A failed plan must fail the job; destructive operations remain blocked unless
   the repository's explicit approval control is satisfied.
8. Each active layer retains an independent backend/state and approval boundary.
9. Raw templates must remain valid YAML, and GitHub `${{ }}` expressions must
   survive rendering unchanged.
10. Generated workflows must work for both HCP Terraform and `azurerm` backends,
    or be conditionally emitted when one backend is required.

These implement controls SR1–SR8, OI1, AR3, SC2, TR1, and GH1 from the factory
risk register.

## 4. Decisions required before implementation

| Decision | Recommended default | Why it must be explicit |
|---|---|---|
| Workflow set for v0.1 | Plan, apply, format/validate, security scan, policy checks, action pinning, and auth test | The design lists fifteen eventual workflows, while the live repo currently has ten |
| Forked PR behavior | Run credential-free validation; skip cloud plan with an explicit neutral summary | Forks do not receive secrets, and untrusted code must not receive a cloud token |
| Destroy approval | Require both the `approved-destroy` label and a protected environment/reviewer for apply | A label alone is not a sufficient production authorization boundary |
| Workflow source | Treat the accepted factory controls as authoritative; port live workflow behavior selectively | Several live workflows predate the factory identity/backend/layer model |
| Terraform version | Derive from `factory-version.json` through one computed value | Prevent workflow/toolchain drift |
| HCP token handling | Decide whether generated repos use a workspace token/variable or dynamic credentials | The architecture prefers no static CI credential, but the proof template uses `TF_API_TOKEN` |

The non-production workload/schema decision in `HANDOFF.md` §1.3 is independent
of workflow promotion. Stage 7 may proceed for the five implemented layers, but
the matrix must be derived from `computed.layers` so a later schema/layer change
does not require workflow surgery.

## 5. Implementation sequence

1. Inventory and classify each live workflow as **promote**, **replace**, or
   **factory-only**.
2. Define shared computed values/tokens for Terraform version, repository default
   branch, backend mode, active layers, and identity variable names.
3. Complete the plan template, including fork-safe behavior and plan-summary
   handling.
4. Add apply with environment binding and per-layer ordering.
5. Add credential-free format/validate, pinning, security, and policy workflows.
6. Add the live OIDC/auth verification workflow without granting apply access.
7. Register every emitted file in `template-manifest.json`.
8. Extend renderer tests for emitted file inventory, permissions, triggers,
   subjects, action pins, backend branches, and residual tokens.
9. Render at least dual-region HCP and single-region `azurerm` fixtures.
10. Validate generated YAML and run the full 208-test baseline.

## 6. Definition of done

Stage 7 is complete only when:

- The manifest emits the agreed workflow set and no undeclared workflow files.
- All 208 existing tests pass and new Stage 7 tests pass.
- Both representative configurations render without unresolved factory tokens.
- A static check proves `permissions: {}`, full-SHA action pins, no wildcard
  subjects, no `pull_request_target`, and environment binding on every apply job.
- Every generated layer is planned independently and apply ordering is explicit.
- Plan errors are not swallowed by `|| true` or equivalent logic.
- Forked PR behavior is intentional, tested, and documented.
- The generated workflow corpus is validated as YAML.
- `factory-version.json`, renderer documentation, `HANDOFF.md`, and the
  changelog reflect completion.
- No workflow is triggered and no Azure/Terraform mutation is performed as part
  of the Stage 7 implementation PR.

## 7. Known blockers outside the Stage 7 code change

- The live Entra registration still lacks the `pull_request` federated
  credential recorded in `HANDOFF.md` §6.2.
- Live Terraform formatting debt and live/corpus divergence remain separate
  reviewable work.
- GitHub required status checks are not enabled, so a successful merge is not
  proof that validation passed.
- The non-prod workload layer still requires the schema/product decision in
  `HANDOFF.md` §1.3.
