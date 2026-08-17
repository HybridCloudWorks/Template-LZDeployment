# Decision 0018 — Brownfield means exclude-and-create, never adoption

- **Status**: **Accepted** — operator-directed 2026-08-17 ("using brownfield
  environments exclude those subscriptions and create new subscriptions that
  are meant for all new deployments … there is a process of integration …
  but that is out of scope of this").
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
