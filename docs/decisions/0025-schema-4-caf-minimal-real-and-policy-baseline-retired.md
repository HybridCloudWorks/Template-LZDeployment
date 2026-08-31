# Decision 0025 — Schema 4.0.0: `caf-minimal` becomes a real hierarchy, and the bespoke policy baseline is retired

- **Status**: **Accepted** — operator-directed 2026-08-31, in answer to the two
  questions TODO 6.4a and the coverage register were left open to ask.
  **Amends [decision 0022](0022-management-group-names-not-shape.md)**, which
  established that the client owns the management groups' *names* and the
  pinned library owns their *shape*. This carves out one exception and says why
  it is not a general licence.
- **Date**: 2026-08-31
- **Deciders**: operator (chose "make it real" over retiring the option, and
  "all 40" over a partial close)
- **Technical depth**: L300 (ALZ architecture definitions, the `alz` provider's
  `library_references` composition, schema versioning)

## Context and Problem Statement

Two unrelated defects both required a breaking schema change, so they land
together rather than as 4.0.0 and 5.0.0 back to back. A client migrating does
it once.

### `caf-minimal` described something that did not exist

The schema said `caf-minimal` deployed "Platform + Landing Zones only". It did
not. Rendering the same configuration under `caf-minimal` and `caf-standard`
produced **byte-identical Terraform**: the architecture selected was the pinned
library's `alz` in both cases, Sandbox and Decommissioned included.

Three artefacts described a hierarchy nobody deployed:

- the schema's own `strategy` description;
- the wizard's resource estimator, which costed `caf-minimal` at 4 management
  groups and `caf-standard` at 9 — **both wrong**, since the pinned library
  defines 12;
- the option label, which at least said "not yet distinct from CAF standard",
  and was the only honest one.

That estimate stopped being cosmetic in #125, where it began gating HCP
Terraform export above the free tier's 500-resource cap.

TODO 6.4a left this open rather than guessing, on the grounds that "trimming a
hierarchy is not a rename" and that dropping groups would strand
`azure.subscriptions.sandbox` and `azure.managementGroups.workloadPlacement`.

### Six governance toggles asked a question already answered

`governance.policyBaseline` carried six booleans — allowed locations, TLS
minimums, NSGs on subnets, public IPs on NICs, diagnostic settings, encryption
at rest. Every one of those controls is enforced by an assignment the pinned ALZ
library ships, and since #123 the client chooses those in the wizard's Policies
step, against the real assignment names.

So the wizard asked the same six questions twice, in two places, with only one
of them connected to anything. The coverage register recorded them as
recorded-not-deployed with the resolution "retire them in a schema major, or map
each to the catalog assignment it duplicates".

## Decision

### `caf-minimal` drops exactly Sandbox and Decommissioned

It now emits its own architecture definition — `<companyShortName>-minimal` —
composed with the pinned library through `library_references`, exactly as the
`custom` strategy already did. Ten management groups instead of twelve.

**Those two, and the choice is forced rather than aesthetic.** Both are direct
children of the root with **no children of their own**, so dropping them
re-parents nothing. Every other library group is Platform, Landing Zones, or a
child of one of those. Dropping Corp or Online instead would strand
`workloadPlacement`, which is precisely the objection TODO 6.4a raised — and it
applies to those groups, not to these.

**The orphan that remains is the sandbox *subscription*, and it is refused
rather than re-homed.** Guard **G31** and the wizard both block a configuration
that selects `caf-minimal` and also sets `azure.subscriptions.sandbox`. Two
alternatives were rejected:

- *Silently drop the placement.* The client would get a subscription outside the
  hierarchy without being told.
- *Place it under Landing Zones instead.* That puts a sandbox subscription under
  a governed archetype — a policy posture nobody chose, discovered later.

Refusing is the only option that cannot be discovered after the fact. It also
has to be an **error**, not a warning: the global layer's `active_placements`
filters slots whose subscription id is *empty*, not slots whose management group
is missing, so a populated sandbox slot reaches the apply and fails there —
after management groups whose ids are **immutable** have already been created.

**This does not reopen decision 0022.** The client still cannot re-nest a group
or attach a different archetype, because an archetype is bound to a group by the
architecture definition and moving a group changes the policy set governing
everything beneath it. `caf-minimal` is a fixed, factory-authored subset — one
alternative shape the factory offers, not a shape the client composes.

### The six policy-baseline booleans are removed

Not mapped to catalog assignments. Mapping would keep two controls that can
disagree, and the Policies step is the one with a generated catalog behind it,
validated against the pinned library by CI.

**`enforcementMode` and `requiredTags` stay.** They are siblings under the same
object and both are consumed — `requiredTags` reaches `FINOPS.md`,
`enforcementMode` reaches the policy assignments. Removing the parent object
wholesale would have taken them too.

## Consequences

- **Breaking, in a way that changes what deploys.** A 3.x configuration
  selecting `caf-minimal` deployed twelve management groups; the same
  configuration at 4.0.0 deploys ten. A client mid-engagement must re-export
  rather than hand-edit `schemaVersion`, and one who has already applied under
  `caf-minimal` should stay on `caf-standard` — management-group ids are
  immutable, and a group that exists cannot be un-created by a render.
- **The HCP free-tier estimate changes for everyone**, because both weights were
  wrong. Estates near the 500-resource cap may now be told they exceed it. That
  is the estimate becoming correct, not becoming stricter.
- **`caf-minimal` now pins the estate to a local architecture definition**, with
  the same consequence the `custom` strategy carries: a library bump updates the
  archetypes and assignments, but the emitted group list is this repository's
  until re-rendered. `caf-standard` remains the only strategy that tracks the
  library's own architecture wholesale, and remains the default.
- **The coverage ledger falls from 40 to 34.** The remaining 34 are the
  docs-shaped groups and the VPN/Bastion SKUs, which are additive work rather
  than a schema change.
- **Six questions the client used to answer are gone.** Anyone who set them was
  recording a preference that reached nothing; the equivalent choice is in the
  Policies step and always was.

## What this does not do

It does not let a client define a hierarchy. There are three strategies and the
factory authors all three; `custom` renames the library's groups and
`caf-minimal` omits two of them, and neither can re-parent a group or change
which archetype governs one. Decision 0022's reasoning is unchanged.
