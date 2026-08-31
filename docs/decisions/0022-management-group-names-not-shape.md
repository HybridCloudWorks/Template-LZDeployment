# Decision 0022 — The client names the management groups; the library shapes them

- **Status**: **Accepted** — plan-approved 2026-08-30 ("Client-named groups in
  the standard ALZ shape; arbitrary nesting deferred"), implemented 2026-08-31.
- **Date**: 2026-08-31
- **Deciders**: operator (approved the names-first scope in the Phase 6 plan)
- **Technical depth**: L300 (ALZ architecture definitions, archetype
  inheritance, `library_references` composition)

## Context and Problem Statement

`azure.managementGroups.customHierarchy` shipped as a free-form flat list of
`{id, displayName, parentId}`, with a repeater UI, a referential-integrity
validator and a schema conditional-`required` behind it. It had **zero
readers**. The management groups a client actually received were the ones the
pinned ALZ library architecture defines, whatever they had typed.

Management-group IDs are immutable in Azure. Changing one after apply means
creating a new group and moving every subscription and assignment into it. So
this is not a defect a client discovers and corrects — it is a one-shot mistake
per engagement, and the wizard was inviting it in detail.

Two things had to be decided: what a client is actually allowed to change, and
how the factory delivers it.

## Decision

**Names, not shape.**

`customHierarchy` becomes a map of renames keyed by the pinned library's own
management-group id:

```json
"customHierarchy": {
  "alz":      { "id": "contoso-alz", "displayName": "Contoso Landing Zones" },
  "platform": { "id": "contoso-platform" }
}
```

Only `id` and `displayName` are the client's. The parent edges and the
archetype each group carries stay exactly as the library declares them.

**Why not the tree the old shape promised.** An archetype is attached to a
management group *by the architecture definition*. Re-nesting a group therefore
changes which archetype — and so which policy set — governs everything beneath
it. Offering arbitrary structure means offering a client the ability to change
the policy posture of their entire estate by moving a node, with no indication
that they have done so, in a way Azure will not let them take back. Names carry
none of that risk and cover the case that actually drives the request:
collision-free, recognisable group IDs in the client's own convention.

**Delivery.** Under `strategy = custom` the renderer synthesizes
`terraform/live/global/lib/architecture_definitions/<org>.alz_architecture_definition.json`
and appends a local `{ custom_url = "${path.root}/lib" }` entry to the `alz`
provider's `library_references`. It **composes** with the pinned remote
reference rather than replacing it: every archetype, policy definition and
policy assignment still comes from `platform/alz` at the pinned ref, and the
local file says only what the groups are called. `custom_url` conflicts with
`path`/`ref`, so it must be its own list element.

`provider "alz"`'s `library_references` was a hardcoded literal with no tokens.
It is templated now, so the pin is stated once, in `factory-version.json`.

**Placement follows the rename.** The five `*_management_group_id` placement
targets are emitted from the same resolution instead of defaulting in
`variables.tf`. Without that, a renamed hierarchy would place every subscription
into a management group that does not exist.

**Workload placement becomes an answer.** `azure.managementGroups.workloadPlacement`
(`corp` | `online` | `landingzones`, default `corp`) replaces
`landing_zones_management_group_id` with `workload_management_group_id`.

State this precisely, because it is commonly misread: it does **not** change how
many policy assignments the workload subscriptions inherit. `online` carries
none of its own and inherits `landingzones`' plus the root's either way. What it
buys is the ability to differentiate `corp` from `online` *later* without moving
the subscription, since `corp` adds five deny-style assignments that `online`
does not. Placing directly at `landingzones` forecloses that distinction.

## Consequences

- **Schema major, 2.2.0 → 3.0.0.** The old `customHierarchy` array cannot be
  read as the new map, and there is no migration: the old value described a tree
  nothing ever built, so there is nothing to preserve.
- Render guard **G29** refuses a rename key the library does not define, two
  groups resolving to the same id, and a `custom` strategy that renames nothing.
  The last is not pedantry — emitting a local architecture identical to the
  library's pins the estate to a copy that a library bump can no longer update.
- The answer-coverage ledger loses its largest entry. `customHierarchy` has a
  real reader now, so the recorded-not-deployed budget drops 44 → 41.
- **Arbitrary nesting stays deferred, not refused.** If a client needs a group
  the library does not define, the mechanism to deliver it now exists — the
  local library is already emitted and composed. What is missing is a decision
  about which archetype a new group inherits, and that is the decision this one
  declines to make on the client's behalf by accident.

## Still open

`strategy` still offers `caf-minimal`, which produces byte-for-byte identical
Terraform to `caf-standard`: the emitted architecture is the library's `alz` in
both cases, including Corp, Online, Sandbox and Decommissioned. That is the same
silent-answer defect this repository has now found five times, and the
answer-coverage check cannot see it — the check verifies that a *key* is read,
not that every *value* of it changes anything. Recorded as REVIEW §23.
