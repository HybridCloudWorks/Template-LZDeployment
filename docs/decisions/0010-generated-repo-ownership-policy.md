# Decision 0010 — Generated-repository ownership policy

- **Status**: **Proposed — awaiting operator ratification.** Nothing below is
  policy until the operator ratifies it in-session; the
  [REVIEW.md](../../REVIEW.md) §13 gate stays closed until then. The
  operator's 2026-08-14 message corrected this record's *premise* (see
  History); it did not ratify the record.
- **Date**: 2026-08-14 (authored); 2026-08-14 (rewritten on premise
  correction, same day)
- **Deciders**: operator (ratification pending); `docs-knowledge-curator`
  (authored both versions)
- **Technical depth**: L200 (ownership policy over a settled mechanism)

## History

- **2026-08-14 (first draft)**: authored as a two-question options paper
  under the premise that this repository is a CBTS engagement factory —
  Q-A (which owner CBTS names) with options A/B/C, Q-B (transfer to the
  client afterward) with options T1/T2.
- **2026-08-14 (premise correction, operator-supplied)**: the operator
  corrected the framing in their own words — "this is NOT a CBTS project,
  this is a personal project… I am the owner since day 1 and have always
  been." Because the record was unratified and unmerged, it was rewritten
  in place rather than superseded; the prior options survive only as the
  "Considered under the prior premise" note below.

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
an explicit per-run choice, never inherited from whoever is logged in.

**The corrected premise** (operator-stated, session-verified 2026-08-14):
this is a personal project. The authenticated GitHub identity is
`saulpatinojr` — a personal account, an **admin** collaborator on
`HybridCloudWorks/Template-LZDeployment`; the repo's owner
`HybridCloudWorks` is an **organization** (second admin collaborator:
`hcw-architect`). The operator states the project has been theirs, under
their ownership, since day 1. Operator, client, and engagement owner are
the same person; there is no engagement counterparty.

What remains open is one question, not two: which `ownerName` /
`ownershipModel` pair the operator's own generated repos use.

### Repository facts that constrain the choice

Verified against the repo 2026-08-14; both survive the premise correction
unchanged.

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
   that name.** `Set-LzFederatedCredential` heals the federation on a broker
   re-run — but by handoff time decision 0004 has the factory copy
   **deleted**, so the owner chosen at render time is permanent in practice.
2. **Risk GH1 makes `personal` a trap, and the tooling already says so.**
   The schema's `ownershipModel` description records that personal accounts
   on the Free plan cannot use environments or branch protection on private
   repos — the broker degrades and names every control it could not apply in
   the bootstrap report rather than skipping silently. The wizard
   (`site/app.js`) warns on `personal`, defaults to `organization`, and its
   hint calls `organization` "the recommended model". Discovery readiness
   check **R09** (`factory/discovery/public/Test-LzTenantReadiness.ps1`)
   **fails** when the declared model does not match the actual account type
   of `ownerName`, and warns when the owner's capabilities are reduced.
   Under the corrected premise this analysis **gains force**: the tempting
   solo-owner shortcut is `ownershipModel: personal` under `saulpatinojr`,
   and that is exactly the configuration that silently loses the
   protected-environment gate the apply identity's `environment:<name>`
   subjects depend on.

## Decision

**Recommendation — explicitly a recommendation, not a decision; ratification
is the operator's call:**

`ownerName` is a **GitHub organization the operator owns**, with
`ownershipModel: organization`. `HybridCloudWorks` is the existing
precedent — it already owns this factory and is an organization the
operator controls. `personal` is not used even as a solo owner, because of
GH1: on a personal Free account the broker's protected environments and
branch protection degrade, removing the gate the apply OIDC subjects
depend on, and fact 1 makes that owner choice permanent in practice.
(`enterprise` remains available where its prerequisites —
`enterpriseSlug`, and `visibility: internal` support — apply; not the
default.)

## Transfer question (formerly Q-B) — moot

The first draft's second question — whether a repo created under one
party's owner is transferred to the other party afterward — assumed a
counterparty that does not exist. Operator, client, and engagement owner
are the same person, so there is no one to transfer to and the question
dissolves. The underlying fact it turned on still stands and is worth
keeping: because the OIDC subjects embed the owner (fact 1), any future
owner change is a re-federation event, not a settings click — one more
reason to name the permanent owner at render time.

## Considered under the prior premise — dissolved by the correction

The first draft optioned Q-A as A (client-owned org from day one) /
B (a CBTS-controlled org per engagement) / C (one shared CBTS org), and
Q-B as T1 (transfer at handoff) / T2 (no transfer). B, C, and T1 existed
only to model a two-party engagement and dissolve with it; A and T2 —
the recommended pair — survive as the single-party recommendation above:
the repo is born under its permanent, operator-owned organization, and no
transfer step ever exists to go wrong. The cross-party trust and
re-federation analysis that ruled out B/C/T1 is preserved in this
record's git history.

## Consequences

*(Of the recommended option, if ratified.)*

- **Positive**: the OIDC subjects are stable for the life of the estate;
  repo, identities and Azure estate share one ownership boundary from
  birth; R09/GH1 validate the owner at discovery; the wizard's
  `organization` default and hint are already correct, so no tooling
  change is required to comply; `HybridCloudWorks` already exists, so no
  new org is needed.
- **Negative / open**: the org's **plan tier** decides whether the
  protected-environment gate actually exists (the broker reports a
  degradation, but reporting is not protection) — the GH1 org-tier
  boundary is unverified (open question 2).
- **Follow-ups** (implementation work, only after ratification):
  1. Record the policy where TODO item 2.6's validation criterion points:
     the wizard's ownership hint and the operator docs reference this
     record.
  2. Add the prerequisite to
     [docs/USER-CHECKLIST.md](../USER-CHECKLIST.md): the owning org exists
     and its plan tier supports the controls the broker sets.
  3. Verify the GH1 org-plan-tier boundary from an environment with the
     access, and fold the answer into open question 2.
  4. Curator pass: reconcile REVIEW.md §13, TODO.md item 2.6, and
     CHANGELOG.md to the ratified state.

## Open questions for the operator

1. **Ratification.** The 2026-08-14 message corrected the premise; it did
   not confirm the rewritten record. Explicit confirmation that generated
   repos use an operator-owned organization (`HybridCloudWorks` or a
   successor) with `ownershipModel: organization` is still pending.
2. **Where exactly is the GH1 plan-tier boundary?** The schema states it
   for personal Free accounts. If an *organization* on the Free plan
   degrades the same controls on private repos, the policy needs a
   minimum-plan statement, not just an ownership-model statement.
   Unverifiable from this repository; needs a GitHub-docs check —
   including for `HybridCloudWorks` itself.

## Ratification

*Pending.* This section is deliberately empty: the body above is the paper
the decision will be taken on, and — per the decision 0009 precedent — it
will not be edited after the fact (the 2026-08-14 rewrite predates
ratification and is recorded in History). Ratification is recorded here, in
the Status line, and in REVIEW.md §13 when the operator answers.
