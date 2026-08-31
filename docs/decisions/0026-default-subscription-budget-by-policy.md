# Decision 0026 — The default subscription budget is deployed by policy, and `finops.budgets` stays documented-only

- **Status**: **Accepted** — operator-directed 2026-08-31, choosing "a new
  answer matching what the policy is" over three alternatives (below).
  **Amends [decision 0017](0017-wizard-scope-vs-emitted-architecture.md)** in
  one place only: `finops.budgets` was the largest remaining example of an
  answer the wizard collects and the architecture does not deploy, and this
  closes it for the common case without pretending to close it for all cases.
- **Date**: 2026-08-31
- **Deciders**: operator
- **Technical depth**: L300 (ALZ custom libraries, archetype overrides,
  DeployIfNotExists policy, Azure Consumption budgets)

## Context and Problem Statement

`docs/finops.md` rendered a table of the client's budgets under a sentence
saying **no layer creates any of them**. That was honest and useless: the client
answered a question about cost control and got a document telling them to go and
do it by hand.

The pinned ALZ library already ships the mechanism. `Deploy-Budget` is a
**DeployIfNotExists** policy definition carried by the `root` archetype — so it
is created at the tenant root in every hierarchy strategy — and the library
**assigns it in no archetype**. It is a complete, tested, Microsoft-maintained
control sitting unused in a library this factory already pins. The upstream
policy FAQ names unassigned custom definitions as a category to review; this is
one.

### Why it could not simply be wired to `finops.budgets`

Two impedance mismatches, either of which alone would have forced the question:

- **Scope.** `Deploy-Budget` places one amount on **every subscription beneath
  one management group**. `finops.budgets` is a list of per-scope budgets whose
  `scope` field is **free text** (the schema's own example is `"prod"`). There
  is no total function from one to the other.
- **Thresholds.** The policy takes **exactly two** — `firstThreshold` and
  `secondThreshold`. `finops.budgets.alertThresholdPercents` is an array whose
  default is three. Mapping the array onto the pair means either dropping a
  threshold the client entered or inventing one they did not.

## Decision

**Add `finops.defaultSubscriptionBudget`** — enabled, management group, amount,
two thresholds, period, contacts — and assign `Deploy-Budget` from it.
**Additive: schema 4.1.0, nothing breaks.** A configuration that omits the block,
or sets `enabled: false`, renders exactly as 4.0.0 did.

**`finops.budgets` stays documented-only**, and `docs/finops.md` now opens the
budget section by naming both mechanisms and saying which one is deployed. The
previous text described one mechanism and disclaimed it; the new text describes
two and disclaims one.

### Rejected alternatives

- *Map `finops.budgets` onto `Deploy-Budget`.* Requires guessing a management
  group from a free-text scope string and silently discarding thresholds. A
  client who entered `[50, 80, 100]` would get alerts at two of them and no
  indication which two.
- *Deploy budgets as `azurerm_consumption_budget_subscription` resources.*
  Covers exactly the subscriptions named at render time. Every subscription
  vended afterwards — which is the point of a landing zone — silently has no
  budget until somebody re-renders. This is the argument that decided it.
- *Keep documenting and do nothing.* Leaves a Microsoft-maintained control
  unused in a library already pinned, for a question the client already answers.

### Three artefacts, because the library takes three

`lib/policy_assignments/Deploy-Budget.alz_policy_assignment.json`, an archetype
override adding it to a copy of the target group's archetype, and an
architecture definition binding that override to the group. That is the
library's own documented sequence, not an invention here.

**A descendant scope resolves correctly, and this was verified rather than
assumed.** The definition lives at the root; the assignment may target any
group. The library's own `corp` archetype assigns `Deny-Public-Endpoints`,
whose policy set is deployed at root, through the same `placeholder` form.

**`enforcementMode` is `Default` and is deliberately NOT wired to
`governance.policyBaseline.enforcementMode`.** That switch downgrades deny-class
guardrails to `DoNotEnforce` so an estate can be observed before it starts
refusing deployments. A budget refuses nothing — it creates a notification —
so there is nothing to observe first, and `DoNotEnforce` would mean a client
enabled a budget and received none.

## Consequences

- **Enabling the budget pins the estate to a local architecture definition,
  even under `caf-standard`.** The architecture is the only thing that binds an
  archetype name to a group, so the override cannot reach the group without one.
  This is the same cost [decision 0025](0025-schema-4-caf-minimal-real-and-policy-baseline-retired.md)
  records for `custom` and `caf-minimal`: a library bump still updates every
  archetype, definition and assignment, but the **group list** is this
  repository's until re-rendered. `caf-standard` **without** the budget remains
  the only shape that tracks the library's architecture wholesale.
- **The architecture gets a distinct name** (`<short>-standard` for the
  budget-only case). Both libraries compose into one set and two architectures
  sharing the name `alz` is a collision, not a merge.
- **Two new guards.** **G32** refuses a budget aimed at a management group the
  chosen strategy does not create — the schema's enum lists all twelve library
  groups and cannot know that `caf-minimal` creates ten. **G33** refuses a
  warning threshold at or above the second: neither is rejected by Azure, and
  both produce a budget that works and tells the client nothing useful.
- **The wizard's resource estimate rises by two** when the budget is enabled,
  which matters because that estimate gates HCP Terraform's 500-resource free
  tier. The budgets the policy then creates are **not** counted: they are made
  by policy remediation and never enter Terraform state.
- **A budget notifies; it does not cap.** Said in the schema, in the wizard, and
  in the generated document, because "cap threshold" invites the opposite
  reading at exactly the moment it matters.

## What this does not do

It does not deploy `finops.budgets`. A client needing a different amount for one
environment, or more than two thresholds, still creates that budget by hand
against the table in `docs/finops.md`. The default budget is a floor under the
whole estate, not a replacement for per-scope budgeting.

It does not choose an amount. `amountUsd` is the one field with no defensible
default, and an enabled budget without one is refused by both the wizard and the
schema.
