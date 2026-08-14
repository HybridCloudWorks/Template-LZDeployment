# Decision 0010 — Generated-repository ownership policy

- **Status**: **Proposed — awaiting operator ratification.** Nothing below is
  policy until the operator ratifies it in-session; the
  [REVIEW.md](../../REVIEW.md) §13 gate stays closed until then.
- **Date**: 2026-08-14 (authored)
- **Deciders**: operator (ratification pending); `docs-knowledge-curator`
  (authored the options paper)
- **Technical depth**: L200 (engagement policy over a settled mechanism)

## Context and Problem Statement

The *mechanism* of generated-repo ownership is settled and needs no change —
[decision 0004](0004-factory-copy-is-a-disposable-installer.md) records it as
its one remaining open question (#3), and REVIEW.md §13 carries it as the
open decision. `factory/schema/lz-config.schema.json` makes
`github.ownershipModel` (`personal | organization | enterprise`) and
`github.ownerName` **required** fields, and
`factory/scaffold/LZFactory.Scaffold.psm1` builds its target as
`"$($Config.github.ownerName)/$($Config.github.repositoryName)"`, creating
the repository there (`gh repo create`) when it does not exist. Ownership is
an explicit per-engagement choice, never inherited from whoever is logged in.

What remains open is **engagement policy, not capability**: which owner CBTS
names, and whether that owner is permanent.

### What has to be decided

Two questions, verbatim from REVIEW.md §13:

- **Q-A** — which value CBTS puts in `github.ownerName` for a typical
  engagement: the client's own organization from day one, a CBTS-controlled
  organization per engagement, or one shared CBTS organization.
- **Q-B** — whether a repository created under a CBTS owner is transferred
  to the client afterward.

### Repository facts that constrain the choice

Verified against the repo 2026-08-14.

1. **The OIDC subjects embed the owner literally.**
   `factory/bootstrap/LZFactory.Bootstrap.psm1` (`New-LzBootstrapPlan`)
   composes
   `$repo = "$($Config.github.ownerName)/$($Config.github.repositoryName)"`
   and issues the plan subject `repo:<owner>/<name>:pull_request` and the
   apply subjects `repo:<owner>/<name>:environment:<env>` — environment
   subjects only on the apply identity, per
   [contract #2](../CROSS-DOMAIN-CONTRACTS.md#2-oidc-identity-split-plan-sp-vs-apply-sp).
   The schema says the same in `ownerName`'s own description: "Combined with
   repositoryName to form the OIDC subject claim." **Change the owner and
   every federated credential names a repository that no longer exists under
   that name.** `Set-LzFederatedCredential` is idempotent and updates a
   credential whose subject differs, so a broker re-run with the corrected
   `ownerName` heals the federation — but by handoff time decision 0004 has
   the factory copy **deleted**, so that re-run means re-obtaining a copy and
   re-authenticating: a partial re-engagement, not a settings click.
2. **The broker hardens whatever owner the repo was created under.**
   `LZFactory.Bootstrap.psm1` reconciles branch protection, required checks,
   environments (`deployment_branch_policy` with `protected_branches=true`,
   never custom policies), variables and secrets on the generated repo, with
   API read-back. The protected environments are the gate the apply
   identity's `environment:<name>` subjects depend on.
3. **Risk GH1 makes `personal` a trap, and the tooling already says so.**
   The schema's `ownershipModel` description records that personal accounts
   on the Free plan cannot use environments or branch protection on private
   repos — the broker degrades and names every control it could not apply in
   the bootstrap report rather than skipping silently. The wizard
   (`site/app.js`) warns on `personal`, defaults to `organization`, and its
   hint calls `organization` "the recommended model". Discovery readiness
   check **R09** (`factory/discovery/public/Test-LzTenantReadiness.ps1`)
   **fails** when the declared model does not match the actual account type
   of `ownerName`, and warns when the owner's capabilities are reduced.
4. **The client's own `gh` session executes the creation.** Decision 0004
   (operator-ratified 2026-08-06): the client runs the motion, on their own
   machine, under their own `gh` and `az` sessions. So whatever `ownerName`
   says, **the client's GitHub account must hold repo-creation rights under
   that owner** at scaffold time. A CBTS-owned `ownerName` therefore means
   either admitting the client's account into a CBTS organization, or CBTS
   running the motion — the second contradicts the ratified model outright.
5. **`visibility: internal` requires `ownershipModel: enterprise`** (schema
   `allOf` + render guard + wizard validation), and `enterprise` requires
   `enterpriseSlug`. Enterprise engagements are supported but carry their
   own prerequisites.

### What could not be verified from this repository alone

Stated plainly, per house rule:

- **GitHub's transfer-time behavior.** That a transferred repo's OIDC token
  carries the *new* owner in its `sub` claim, and exactly which settings
  (secrets, environments, protection rules) survive a transfer onto the
  destination owner's plan, are GitHub-platform facts, not repo facts. The
  subject-composition consequence in fact 1 is verified from the broker's
  code; the platform half should be re-checked against GitHub's docs at
  implementation time (the `MicrosoftDocs/azure-docs`-on-GitHub route that
  settled item 2.17 has a `github/docs` analogue).
- **Organization plan tiers.** GH1 as written covers *personal* accounts on
  the Free plan. Whether an **organization** on the Free plan degrades the
  same controls on a private repo could not be verified here; see open
  question 3.

## Considered Options

### Q-A — the owner at creation time

#### Option A — the client's own organization, from day one

`ownerName` is a GitHub organization the client owns;
`ownershipModel: organization` (or `enterprise` where the client has one).

- **Fit with decision 0004**: exact. The client's `gh` session creates a
  repo in the client's own org — no cross-party membership, no CBTS
  operator at the keyboard. The repo, the Azure estate, and the identities
  that bind them live inside **one** ownership boundary from birth.
- **OIDC**: the subjects never change, because the owner never changes.
  Q-B evaporates.
- **Verification**: R09 and the GH1 warning run against the org that will
  own the repo forever, so a plan-tier problem surfaces at discovery, not
  at handoff.
- **Costs**: the client must have (or create) a GitHub organization before
  the engagement — a pre-engagement checklist item, not tooling; the org's
  plan tier decides whether the protected-environment gate actually exists
  (the broker reports the degradation, but reporting is not protection);
  CBTS holds no standing access after the engagement unless invited as a
  collaborator, which is a support-contract question, not an ownership one.

#### Option B — a CBTS-controlled organization per engagement

- **Fit with decision 0004**: inverted. The client's `gh` session must be
  granted repo-creation rights inside a CBTS org — CBTS onboards and
  offboards client GitHub accounts per engagement — or CBTS runs the
  motion, which the ratified model rules out.
- **OIDC**: every apply credential binds `repo:<cbts-org>/…` while the
  Azure roles live in the **client's** tenant. That is a standing
  cross-party trust: CBTS org admins control the repository whose protected
  environments can assume Contributor on the client's subscriptions. This
  is precisely the least-surprising-privilege-placement test decision 0006
  applied, and this option fails it.
- **Forces Q-B**: handoff eventually requires a transfer, with the
  re-federation cost in fact 1.

#### Option C — one shared CBTS organization for all engagements

Everything Option B costs, plus cross-client blast radius: every client's
apply path concentrates in one org, so one compromised org-admin account
touches every engagement, and org-member visibility spans clients even with
`visibility: private`. Named for completeness; not seriously entertained.

### Q-B — transfer to the client afterward

Arises only when Q-A lands on B or C.

#### Option T1 — transfer as a standard handoff step

The transfer changes the `<owner>` in every `repo:<owner>/<name>:*` subject
GitHub will thereafter issue, so **every federated credential the broker
created goes stale at the moment of transfer** — plan and apply alike, and
CI is fully red until they are re-issued. The healing re-run needs a factory
copy that decision 0004 has already deleted (fact 1). What else survives the
transfer on GitHub's side is unverified (see above). A routine handoff step
that silently severs the deployment identity is the quiet-failure shape this
repo's registers exist to prevent.

#### Option T2 — no transfer; the repo is born under its permanent owner

This is Option A restated from the other end: the only ownership policy with
no re-federation event is the one where the owner never changes.

## Decision

**Recommendation — explicitly a recommendation, not a decision; ratification
is the operator's call:**

- **Q-A: Option A** — `ownerName` is the **client's own organization from
  day one**, with `ownershipModel: organization` (`enterprise` where
  applicable); `personal` is never used for a real engagement (GH1).
  Because decision 0004 already puts the client's `gh` session at the
  keyboard, any CBTS-owned owner adds a cross-party membership step the
  ratified model does not want — and because the OIDC subjects embed the
  owner literally, any owner chosen "for now" turns handoff into a
  re-federation event. The wizard's existing default and hint already say
  this; ratification makes it policy rather than a default.
- **Q-B: Option T2** — repositories are **not** created under a CBTS owner,
  so transfer never arises as standard practice. If an exceptional
  engagement starts under a CBTS owner anyway, the transfer must be treated
  as a re-federation: re-run the broker's federated-credential
  reconciliation with the corrected `ownerName` against the transferred
  repo, verify the read-back, and record the exception.

## Consequences

*(Of the recommended option, if ratified.)*

- **Positive**: no transfer step exists to go wrong; the OIDC subjects are
  stable for the life of the estate; repo, identities and Azure estate share
  one ownership boundary from birth; R09/GH1 validate the permanent owner at
  discovery; the wizard default is already correct, so no tooling change is
  required to comply.
- **Negative**: a client GitHub organization becomes a **pre-engagement
  prerequisite**, including a plan tier that supports protected environments
  and branch protection on private repos — a cost conversation with the
  client before the wizard runs; CBTS retains no standing access after
  disposal unless separately granted; the org-tier boundary of GH1 is
  unverified (open question 3).
- **Follow-ups** (implementation work, only after ratification):
  1. Record the policy where TODO item 2.6's validation criterion points:
     the wizard's ownership hint and the operator docs reference this
     record.
  2. Add the pre-engagement prerequisite to
     [docs/USER-CHECKLIST.md](../USER-CHECKLIST.md): client org exists, plan
     tier supports the controls the broker sets, and the client account
     running the motion can create repositories in it.
  3. Verify the GitHub-platform half of fact 1 (transfer semantics, org
     Free-plan control set) from an environment with the access, and fold
     the answer into open question 3.
  4. Curator pass: reconcile REVIEW.md §13, TODO.md item 2.6, and
     CHANGELOG.md to the ratified state (deliberately not done in this
     authoring pass beyond recording that the paper exists).

## Open questions for the operator

1. **Does a typical CBTS engagement client already have a GitHub
   organization?** A usual "no" does not change the recommendation, but it
   promotes org creation into the engagement runbook and makes the plan-tier
   cost conversation part of pre-sales rather than a discovery surprise.
2. **Does CBTS need standing post-engagement access** (support or managed
   service)? If so, that is a collaborator/team grant on the client-owned
   repo — an access policy to record, not a reason to own the repo.
3. **Where exactly is the GH1 plan-tier boundary?** The schema states it for
   personal Free accounts. If an *organization* on the Free plan degrades
   the same controls on private repos, the policy needs a minimum-plan
   statement, not just an ownership-model statement. Unverifiable from this
   repository; needs a GitHub-docs check.
4. **Are any near-term engagements `enterprise`-model** (needing
   `visibility: internal` and `enterpriseSlug`)? If yes, the pre-engagement
   checklist gains the enterprise-slug and Actions-policy discovery items.

## Ratification

*Pending.* This section is deliberately empty: the body above is the paper
the decision will be taken on, and — per the decision 0009 precedent — it
will not be edited after the fact. Ratification is recorded here, in the
Status line, and in REVIEW.md §13 when the operator answers.
