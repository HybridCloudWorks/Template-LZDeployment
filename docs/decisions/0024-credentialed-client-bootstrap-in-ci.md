# Decision 0024 — The credentialed engagement may run in CI, behind a reviewer and a typed confirmation

- **Status**: **Accepted** — operator-ratified 2026-08-31, in answer to the
  question TODO 6.6a was left open to ask.
  **Amends [decision 0004](0004-factory-copy-is-a-disposable-installer.md)**
  further, in the same direction
  [decision 0014](0014-delivery-auth-app-pat-and-template-instantiation.md)
  already took it. It does not replace either.
- **Date**: 2026-08-31
- **Deciders**: operator (ratified the CI path 2026-08-31)
- **Technical depth**: L300 (federated credentials, App-token delivery auth,
  environment protection rules)

## Context and Problem Statement

Decision 0004 ratified that the client runs the engagement on their own machine:
"it is the client's own `gh` and `az` sessions that create the estate", which is
what makes the tenant-confirmation step load-bearing. Decision 0014 then amended
one word of that — **delivery** no longer *requires* an interactive session,
because `Initialize-LzDeliveryAuth` accepts a GitHub App token or a PAT.

What 0014 did not cover is **discovery and the bootstrap broker**. The broker
creates Entra applications, federated credentials and RBAC. That is the run 0004
had in mind, and the one PR #125 declined to move into CI without asking,
because doing so is a change to the security model rather than an extension of
it: it swaps an interactive session the client is sitting in front of for a
stored principal they are not, on exactly the run that creates the estate.

## Decision

**The credentialed engagement may run in GitHub Actions, as an opt-in, and the
client-local motion remains the default and remains ratified.**

`.github/workflows/client-bootstrap.yml` runs
`scripts/Invoke-CustomerEngagement.ps1 -Phase all` — discovery → broker →
render → validate → scaffold — under four constraints, each standing in for
something the local motion had for free:

| The local motion had | The CI path substitutes |
|---|---|
| A human choosing to run it | `workflow_dispatch` only. Never `push`, never `pull_request`. |
| A human present at the moment of creation | A **protected environment** with required reviewers. An environment with no reviewers configured makes this job strictly weaker than the motion it replaces. |
| The operator seeing which tenant they were signed in to | A **typed tenant confirmation**, checked against `azure.tenantId` in the committed answer record, **before `azure/login`** — a run aimed at the wrong tenant fails while it is still harmless. The environment's own `LZ_BOOTSTRAP_TENANT_ID` is checked against the same record in the same step, because that variable — not the typed input — is what `azure/login` authenticates to. |
| `-Apply` being something you type | An explicit `apply` input, default `false`. Without it the run is plan-only and mutates nothing. |

**`-AllowNotReady` is deliberately not exposed.** Under `-Apply` the engagement
wrapper runs discovery with `-FailOnNotReady`, so a tenant with blocking
findings stops before the broker. An input that skips that gate is the one input
that would get clicked past, and skipping it is precisely what the gate exists to
prevent.

**Credentials.** Azure is federated — the bootstrap principal trusts this
repository's environment rather than holding a password — and GitHub uses
decision 0014's App path. Note that `LZ_GITHUB_APP_PRIVATE_KEY_PATH` is a
*path*: the workflow writes the secret to a file under `RUNNER_TEMP` and removes
it in an `always()` step, because handing that variable a PEM body fails inside
`Initialize-LzDeliveryAuth` with a misleading "does not exist".

## Consequences

- **The principal is client-created, and this is not incidental.** The broker
  creates the OIDC identities the *generated* repository's workflows federate
  with; on the first run there is nothing to authenticate as. So a human creates
  this one, once, by hand, with the permissions
  `docs/USER-CHECKLIST.md` lists. There is no bootstrap that bootstraps itself.
- **The reviewer gate is the control, not the automation.** If the
  `client-bootstrap` environment is configured without required reviewers, every
  argument above collapses and the CI path is worse than the local one. That is
  the single thing to check when auditing this.
- **A privileged principal now exists that the client cannot watch.** It is
  federated rather than stored, and it is gated, but it is real. That is the
  cost of the option and it should be stated when the option is offered, not
  discovered later.
- **0004's model is unchanged as the default.** A client who wants to run the
  engagement from their own machine loses nothing and needs none of this.

## What this does not do

It does not make the engagement automatic. Nothing triggers this workflow but a
person choosing to, confirming the tenant, and a reviewer approving. The moment
that stops being true, this decision no longer describes what is deployed.
