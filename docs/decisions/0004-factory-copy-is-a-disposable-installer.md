# Decision 0004 — The factory copy is a disposable installer, not a client asset

**Date**: 2026-08-06
**Status**: Accepted — **operator-ratified 2026-08-06**
**Context**: Operator correction of the Phase 1 mental model. Supersedes the
ambiguity left open by PROD-TODO Phase 1 CRUD ("retained as the client's
factory instance **or** retired after the customer repo takes over — Phase 6
decision") and narrows [decision 0001](0001-private-copy-over-public-fork.md).

> **Ratification (2026-08-06).** This record was written from an inference and
> has since been confirmed by the operator in their own words:
>
> > "Customer forks (or clones, whatever is better) the repo to INSTALL THE
> > ARTIFACTS that will run on a local machine to CREATE LANDING ZONE
> > COMPONENTS. Essentially a copy/paste of the repo and once it's ran and the
> > LZ files are created, the repo WILL be deleted. The LZ ARTIFACTS is a set
> > of files that together will create all the TF files, handshakes, loaders,
> > etc for a Landing Zone deployment for 1 PARTICULAR client only. Most
> > importantly before it creates these files, it will ALSO create a new repo
> > and THAT will be the source control for the clients Landing Zone
> > deployment."
>
> Three things this settles beyond what the record originally claimed:
> **the copy mechanic is explicitly the operator's indifference point**
> ("forks (or clones, whatever is better)"), so no tooling may depend on it
> being a fork; **the client runs it**, on their own machine; and **the new
> repository is created before the landing-zone files are produced**, so repo
> creation is part of the motion rather than a publishing step bolted on at
> the end. Open questions 1, 2 and 4 below are resolved accordingly.

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

### Resolved by the 2026-08-06 ratification

1. **Does the disposable copy ever exist on GitHub, or is it local-only?**
   *Either is acceptable* — "forks (or clones, whatever is better)". The
   consequence is that no tooling may **assume** a fork: the motion has to work
   from a plain clone or a downloaded archive with no GitHub-side
   representation at all.

   Decision 0001's disclosure concern therefore survives as a *preference*
   rather than a requirement: a fork of a public repo is public, and the
   legacy bootstrap commits `.lz-bootloader-state.json` (tenant and
   subscription IDs). A local clone has no such surface. **Prefer the clone**;
   if a client does fork, decision 0001's private-copy guidance applies.

2. **Should `Initialize-ClientFork.ps1` be retired or retargeted?**
   Its hardening stages (Actions enablement, branch protection, required
   checks, required approvals, secret-scanning read-back) target the
   disposable copy and are **not part of the client motion** — the broker
   already performs that class of work on the surviving generated repo. The
   script is not deleted here, because its `-CreatePrivateCopy` mirror
   mechanic is still the documented way to *obtain* a private copy, and
   because deleting an operator entry point is the operator's call, not a
   documentation change's. It is marked PLANNING-ONLY for the client motion
   and tracked in TODO.md for disposition.

   *Update 2026-08-07*: disposition resolved by
   [decision 0007](0007-retire-client-copy-hardening.md) — the hardening
   stages are retired; the script survives as the `-CreatePrivateCopy`
   mechanic only.

4. **Who physically runs the local machine?** The **client**. Their `gh` and
   `az` sessions therefore create the estate, which is what makes the
   confirm-the-tenant step (PROD-TODO Phase 2) load-bearing rather than
   ceremonial.

### Still open

3. **Which account or org owns the generated repo at creation time, and is it
   transferred afterward?**

   The *mechanism* is not in question — this is settled in the tooling and
   needs no change. `factory/schema/lz-config.schema.json` makes
   `github.ownershipModel` (`personal|org|enterprise`) and `github.ownerName`
   **required** wizard fields, and
   `factory/scaffold/LZFactory.Scaffold.psm1` builds its target as
   `"$($Config.github.ownerName)/$($Config.github.repositoryName)"`. Ownership
   is therefore an explicit per-engagement choice, never inherited from
   whoever happens to be logged in, and an org-owned landing zone is a
   supported configuration today.

   What remains open is **engagement policy, not capability**: which value
   CBTS should put in `ownerName` for a typical engagement, and whether a
   repository created under one owner is expected to be transferred to the
   client afterward. Note that `ownershipModel` is not cosmetic — the schema
   flags risk GH1, that personal accounts on the Free plan cannot use
   protected environments, which is the control the apply identity's
   `environment:<name>` OIDC subjects depend on. Choosing `personal` for a
   real engagement silently removes the apply gate.
