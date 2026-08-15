# Decision 0016 — Emitted workflows stay self-contained (thin-caller pattern rejected)

- **Status**: **Accepted** — operator-ratified 2026-08-15, during the
  generator-only refactor
  ([decision 0013](0013-generator-only-avm-architecture.md)). This record
  documents a **deliberate rejection** of a pattern the refactor directive
  itself proposed, so the contradiction is resolved on the record rather
  than re-litigated later.
- **Date**: 2026-08-15
- **Deciders**: operator (ratified 2026-08-15); recorded by
  `docs-knowledge-curator`
- **Technical depth**: L200 (workflow architecture over settled
  mechanisms)

## Context and Problem Statement

The refactor directive proposed emitting **"thin caller"** workflows into
the generated repository — stubs whose jobs `uses:` a reusable workflow
maintained in another repository, so workflow logic could be updated
centrally. The same directive also mandates that the generated repository
be **permanent and standalone, with no dependency on the factory**. These
two requirements conflict: a thin caller must reference a reusable
workflow living in some other repository, recreating at run time exactly
the external dependency the directive orders removed — every CI run of
every generated repository would depend on that other repository existing,
staying compatible, and staying trustworthy.

## Considered Options

- **Option A — self-contained emitted workflows.** Each generated
  repository carries full workflow definitions
  (`factory/templates/.github/workflows/*.tmpl`: plan, apply, auth-test,
  fmt/validate, policy-diff guardrails, security scan, and the pinning
  policy itself). Updates reach existing repositories only by
  regeneration or Renovate-style PRs — no central kill-switch, but no
  external trust surface either.
- **Option B — thin callers over a shared reusable-workflow library.**
  Central updates for free, at the cost of a standing cross-repository
  dependency, a supply-chain trust decision delegated to whoever controls
  the library, and a direct violation of the standalone mandate.

## Decision

**Option A.** Emitted workflows are **self-contained**:

- every third-party action reference is **SHA-pinned** (full 40-character
  commit SHA, version noted in a trailing comment);
- jobs declare **least-privilege `permissions`**, with `id-token: write`
  present only where OIDC federation is exchanged;
- the invariants are enforced twice — at generation time by validation
  gate **V05** (`workflow-pinning-policy`,
  `factory/validate/LZFactory.Validate.psm1`), which scaffold delivery
  refuses to proceed without, and continuously inside the generated
  repository by the emitted `action-pinning-policy.yml` workflow.

## Consequences

- **Positive**: the generated repository is auditable and runnable in
  isolation on day one and year five; its CI trust surface is exactly the
  SHAs it pins; the factory can be deleted (decision 0004's whole point)
  without orphaning anything.
- **Negative**: a workflow fix does not propagate to already-delivered
  repositories — each one updates on its own cadence, and a fleet-wide
  fix means a fleet of PRs. Accepted: generated repositories are
  per-client estates, not a centrally-operated fleet.
- **Revisit condition**: if a stable, public reusable-workflow library
  **the operator trusts** emerges, this decision can be reconsidered — as
  a new record superseding this one, weighing that library's supply-chain
  posture explicitly.
