# Decision 0004 — The factory copy is a disposable installer, not a client asset

**Date**: 2026-08-06
**Status**: Accepted
**Context**: Operator correction of the Phase 1 mental model. Supersedes the
ambiguity left open by PROD-TODO Phase 1 CRUD ("retained as the client's
factory instance **or** retired after the customer repo takes over — Phase 6
decision") and narrows [decision 0001](0001-private-copy-over-public-fork.md).

## Decision

A client's copy of this repository exists **only to be run once on a local
machine and then deleted**. It is an installer for the factory artifacts, not
a repository anyone governs, protects, or maintains.

The sequence is:

1. Copy this repo to a local machine (fork, clone, or download — the mechanic
   is not load-bearing).
2. Run the factory tooling locally. It creates a **new, separate repository**
   and populates it with the Terraform, OIDC federation, loaders, and workflows
   for **exactly one** client's landing zone.
3. That new repository is the client's landing-zone source control from then
   on. It is the deliverable.
4. The factory copy is deleted.

## What this means in practice

- **The factory copy is never hardened.** No branch protection, no required
  status checks, no required approvals, no environments, no secrets. Those
  settings protect long-lived repos; this one lives for hours and is never
  merged into.
- **The generated repo is hardened, by the broker.**
  `factory/bootstrap/LZFactory.Bootstrap.psm1` (`Reconcile branch protection on
  the generated repository's default branch`, line ~585) already configures
  branch protection, required checks (`repository-scan` by default, override
  with `LZ_REQUIRED_STATUS_CHECKS`), environments, variables, and secrets on
  the surviving repo, and reads them back through the GitHub API. That is the
  correct and sufficient place for this.
- **Factory CI is upstream's development gate, not part of a client run.**
  A client executing the motion does not need Factory CI to pass, or GitHub
  Actions enabled, in their disposable copy.
- **The first step of a client run is not a GitHub settings task.** It is
  toolchain + authentication + confirming the target tenant, then the `site/`
  wizard.

## Consequences

- [`scripts/Initialize-ClientFork.ps1`](../../scripts/Initialize-ClientFork.ps1)
  hardens the *disposable* repo. Under this decision that is the wrong target.
  Its `-CreatePrivateCopy` mirror mechanic remains useful for *obtaining* the
  copy; its Actions/protection/secret-scanning/read-back stages do not apply.
  Disposition is an open question below.
- Decision 0001's *rationale* survives — a public copy still leaks
  `.lz-bootloader-state.json` (tenant and subscription IDs) **if the copy is
  ever pushed to GitHub**. Its *remedy* (a governed private copy per client)
  is heavier than this model needs. If the copy never leaves local disk, the
  disclosure surface is zero.
- PROD-TODO Phase 6 "Dispose the clone" is not an optional tail step. It is
  the defined end of every engagement, and the factory copy is in scope for
  deletion — not merely its local working tree.
- The MUST-NOT-DELETE list in
  [docs/runbooks/engagement-disposal.md](../runbooks/engagement-disposal.md)
  is unchanged and remains authoritative: the generated repo, the Azure
  resources and Terraform state, and the landing-zone identities survive.
  They are the deliverable.

## Open questions

These do not block the decision above but change how it is implemented:

1. Does the disposable copy ever exist on GitHub, or is it local-only? If
   local-only, no GitHub-side setup applies to it at all.
2. Should `Initialize-ClientFork.ps1` be retired, or retargeted at the
   generated repo (where it would overlap the broker)?
3. Which account/org owns the generated repo at creation time, and is it
   transferred afterward?
4. Who physically runs the local machine — an HCW engineer or the client?
   This determines whose `gh` and `az` sessions create the estate.
