# Decision 0018 — Brownfield means exclude-and-create, never adoption

- **Status**: **Accepted** — operator-directed 2026-08-17 ("using brownfield
  environments exclude those subscriptions and create new subscriptions that
  are meant for all new deployments … there is a process of integration …
  but that is out of scope of this").
- **Amended 2026-08-31** (schema 3.2.0): exclusion is still the default and
  still what happens to a subscription nobody mentions, but a client may now say
  otherwise **per subscription**, and the amendment records what they were told
  when they did. See "The 2026-08-31 amendment" below.
- **Date**: 2026-08-17
- **Deciders**: operator (directed the redefinition and the out-of-scope
  boundary); recorded during the schema 2.2.0 change set
- **Technical depth**: L200 (deployment-strategy semantics; guard and schema
  surface)

## Context and Problem Statement

Since Stage 11, "brownfield" in this factory meant *adoption*: discover the
existing estate, classify each resource (Adopt / Ignore / Replace /
Require-Approval), and generate `terraform import` blocks so the landing
zone takes ownership of pre-existing resources. That machinery
(`brownfield-import.ps1`/`.sh`, `factory/import/`, `Test-Import.ps1`) was
already quarantined: its import-block generation targeted the deleted
bespoke modules' resource addresses, and re-targeting it against the AVM
pattern modules' internal addresses was an open item (CLASSIFICATION.md
UNRESOLVED-2).

The operator resolved the question by redefining the term. In a brownfield
tenant, the landing zone is built on **new subscriptions created for all new
deployments**; the existing subscriptions are **excluded**, and integrating
what runs in them is a separate engagement outside this tool.

## Decision

1. **Brownfield = exclude-and-create.** `deploymentStrategy.mode =
   'brownfield'` now means: the new estate is deployed to new (or new-empty)
   subscriptions, and the pre-existing subscriptions listed in
   `deploymentStrategy.brownfield.excludedSubscriptionIds` are structurally
   excluded — never placed in the new management-group hierarchy, never
   granted RBAC, never targeted by policy from this landing zone, never
   planned, imported, or modified.
2. **The import machinery is removed**, not re-targeted:
   `brownfield-import.ps1`, `brownfield-import.sh`,
   `factory/import/LZFactory.Import.psm1`,
   `factory/import/brownfield-classifications.schema.json`, and
   `factory/tests/Test-Import.ps1` are deleted; the CI suite registration and
   template references go with them. This closes CLASSIFICATION.md
   UNRESOLVED-2.
3. **Schema 2.2.0** replaces the import-era brownfield options
   (`defaultClassification`, `generateImportBlocks`, `generateImportCommands`,
   `allowDestructivePlans`) with `excludedSubscriptionIds` (array of GUIDs)
   and `inventoryExistingPolicies` (default true).
4. **Discovery stays read-only** and, when `inventoryExistingPolicies` is
   true, inventories existing tenant-scope policy assignments so collisions
   with the new baseline are visible before the first policy apply.
5. **Guard G26** blocks any configuration in which an excluded subscription
   ID also appears in an `azure.subscriptions` slot — a subscription cannot
   be both excluded and part of the new estate.

## Consequences

- The wizard's brownfield step collects the exclusion list and the policy
  inventory opt-in; all four import sub-options are gone.
- The destroy-protection gate in the generated repository is unchanged — it
  protects the new estate, not the excluded one.
- Integration of existing deployments (workload migration, resource
  adoption) is explicitly out of scope for the factory and the generated
  pipeline; it is a separate engagement.
- Subscription creation for the new estate is decision
  [0020](0020-subscription-vending.md) (vending).

## Supersedes / relates

- Closes CLASSIFICATION.md UNRESOLVED-2 (quarantined import generator).
- Narrows the Stage 11 scope recorded in the pre-0.11.0 checklists; those
  sections are rewritten in `docs/USER-CHECKLIST.md` and the emitted
  `USER-CHECKLIST.md.tmpl` / `README.md.tmpl`.


## The 2026-08-31 amendment — per-subscription dispositions

### What was wrong with a flat exclusion list

`excludedSubscriptionIds` says what the landing zone must never touch. It has no
way to say the opposite, so a client who genuinely wanted an existing
subscription governed had two options: leave it out of the list, which is not a
decision anybody records, or not use the factory. The list answered the
question the ADR asked and none of the questions clients actually have.

### What changed

`deploymentStrategy.brownfield.dispositions` maps a subscription ID to
`place-now` or `defer`. A subscription with no entry is excluded — the ADR 0018
behaviour, unchanged, and still the answer for anything nobody thought about.

**`place-now` requires a typed acknowledgement**, checked against an exact
sentence naming that subscription, by the wizard at export and by render guard
G30 at render. It is not a boolean, on the same reasoning as the
state-access-flip workflow's typed confirmation: a checkbox records that
somebody clicked, and what needs recording here is that somebody read what
placing an existing subscription does.

What it does is worth restating, because the third item is the one people miss:

- **Audit** assignments start reporting non-compliance against resources built
  under different rules. Information, not damage.
- **Deny** assignments do not touch what exists — but they refuse the next
  *change* to it. A pipeline that has worked for years can fail on its next run.
- **DeployIfNotExists and Modify** assignments **create and change things**:
  diagnostic settings, agent extensions, tags, private DNS records. On a
  schedule, or on the next resource write.

**`defer` generates a document.** `docs/subscription-onboarding.md` is emitted
into the generated repository, listing the deferred subscriptions with the
client's own notes and the procedure for onboarding one later — inventory the
compliance impact first, exempt or fix before moving, then move, then record it
back in the answer record. It is emitted only when something is actually
deferred; a document about a decision nobody took is noise.

### What did not change

**Governance only. No resource is ever imported into Terraform state.** Placing
a subscription moves it under a management group so policy applies to it. It
does not bring its resources under Terraform management, and this factory still
has no import path. That remains a separate engagement, exactly as this ADR
said.
