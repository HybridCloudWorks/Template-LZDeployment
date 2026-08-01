# Decision 0001 — Private copy per client, not a literal GitHub fork

**Date**: 2026-08-01
**Status**: Accepted
**Context**: PROD-TODO Phase 1 (fork mechanic and visibility)

## Decision

Each client receives a **private copy** of the factory repository, created by
[`scripts/Initialize-ClientFork.ps1`](../../scripts/Initialize-ClientFork.ps1)
with `-CreatePrivateCopy` (a private repo plus a mirror push of the source),
not a literal GitHub fork.

## Rationale

- A GitHub fork of a public repository is **always public**. The factory's
  motion puts client-adjacent configuration into the fork's settings and
  branches.
- The legacy bootstrap (`scripts/Start-LandingZoneBootstrap.ps1`, phase 9
  `Create-BootstrapPR`) has historically committed
  `.lz-bootloader-state.json` — tenant ID, subscription ID, SP app IDs — to
  bootstrap PR branches. On a public fork that is a disclosure.
- Forks and copies alike inherit none of: Actions enablement, branch
  protection, secrets/variables, environments, third-party integrations — so
  the fork mechanic buys no setup convenience over a copy.
  `Initialize-ClientFork.ps1` configures and API-read-back-verifies these on
  either mechanic.

## Consequences

- **No fork-network pull requests** from upstream to the client copy; GitHub's
  fork-based PR flow is unavailable.
- **Upstream sync** happens by mirror push from a fresh upstream clone, or by
  re-running the copy. The customer's generated repo is upgraded separately
  via `scaffold-copy.ps1` existing-repo mode — see
  [docs/runbooks/engagement-lifecycle.md](../runbooks/engagement-lifecycle.md).
- Per-client enablement (Actions, protection, secret scanning, required
  approvals) is scripted, not tribal:
  `scripts/Initialize-ClientFork.ps1 -Repository <owner>/<name>`.
