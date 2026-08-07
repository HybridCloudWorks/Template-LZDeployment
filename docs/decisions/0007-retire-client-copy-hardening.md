# Decision 0007 — Retire `Initialize-ClientFork.ps1`'s hardening stages; keep `-CreatePrivateCopy`

- **Status**: Accepted — operator-ratified in-session 2026-08-07
- **Date**: 2026-08-07
- **Deciders**: operator (ratified 2026-08-07); `github-actions-engineer`
  (implemented)
- **Technical depth**: L300 (implementation)

## Context and Problem Statement

[`scripts/Initialize-ClientFork.ps1`](../../scripts/Initialize-ClientFork.ps1)
was written under decision 0001's model, where each client's copy of the
factory was a governed private repository: it created the private copy
(mirror push) and then hardened it — GitHub Actions enablement, classic
branch protection with required status checks and approvals ≥ 1,
secret-scanning / push-protection configuration, and a full API read-back
table.

[Decision 0004](0004-factory-copy-is-a-disposable-installer.md)
(operator-ratified 2026-08-06) invalidated the hardening half of that model:
the factory copy is a **disposable installer** that lives for hours, is never
merged into, and is deleted at the end of the engagement — "the factory copy
is never hardened". The class of work the script performs already has a
correct owner for the repository that *does* survive: the broker
(`factory/bootstrap/LZFactory.Bootstrap.psm1`, ~line 585) configures branch
protection, required checks, environments, variables, and secrets on the
**generated** repository and reads them back through the GitHub API. The
script's `-CreatePrivateCopy` mirror mechanic, by contrast, remains the
documented way to *obtain* a private copy when the copy exists on GitHub at
all (decision 0001's disclosure rationale survives as a preference).

Decision 0004 left the disposition as its open question 2 (tracked as
TODO.md item 2.2, REVIEW.md §12): retire the hardening stages, or retarget
them. Deleting an operator entry point is the operator's call, which is why
the question waited for ratification instead of being closed by a cleanup
pass.

## Considered Options

1. **Retire the hardening stages** — strip the script down to the
   private-copy mechanic (`-CreatePrivateCopy` + visibility read-back);
   the broker remains the sole hardening owner, for the only repo worth
   hardening (the generated one). The upstream factory repo's own
   protection (TODO.md item 4.2) is a one-time administration task served
   by the prepared `gh api` payload route, not a reason to keep a
   packaged hardening script pointed at client copies.
2. **Retarget the script at the generated repo** — keep the stages but aim
   them at the scaffold output, reconciling the overlap with the broker.
   This duplicates `LZFactory.Bootstrap.psm1`'s existing, tested
   reconciliation (protection payloads, required-check lists, read-backs)
   in a second dialect: two owners for one contract, drift guaranteed, and
   no capability gained — everything the script would do there, the broker
   already does inside the engagement motion.

## Decision

Chosen option: **retire the hardening stages**, because under decision 0004
their only target class (the factory copy) must never be hardened, and their
only legitimate target class (the generated repo) already has a sole,
correct, tested owner in the broker — retargeting would create a second
owner for the same contract.

Retired with the stages: the `-Branch`, `-RequiredApprovals`,
`-RequiredChecks`, and `-EnforceAdmins` parameters (used only by the retired
stages), the Actions-enablement / branch-protection / secret-scanning
sections, and their read-back rows. Surviving: `-Repository`,
`-SourceRepository`, `-CreatePrivateCopy`, `-Apply`, the plan-first
convention, the mirror-push procedure with its bootstrap-branch residue
warning, the public-visibility warning, and the visibility read-back row.

## Consequences

- **Positive**: one hardening owner — the broker, for generated repos; the
  factory copy is never hardened anywhere in the tooling, closing the
  wrong-target path decision 0004 flagged; the script's help now matches
  what a client run actually needs from it (obtaining a private copy);
  live docs no longer steer operators toward hardening a repo that will be
  deleted.
- **Negative**: the upstream factory repo's protection (TODO.md item 4.2)
  loses its packaged script route and is served only by the prepared
  `gh api ... /branches/main/protection --input <payload>` route — an
  acceptable cost for a one-time, single-repo administration task (and the
  script's approvals ≥ 1 floor deadlocked that single-owner repo anyway).
- **Follow-ups**: none open. The script file is deliberately **not
  deleted** — `-CreatePrivateCopy` survives in it; decision 0001's
  private-copy rationale is unchanged. Decision 0004's open question 2 is
  resolved by this record.
