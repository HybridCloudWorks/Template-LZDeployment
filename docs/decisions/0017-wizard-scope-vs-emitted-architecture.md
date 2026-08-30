# Decision 0017 — The wizard keeps its full scope; the emitted architecture does not deploy every answer

- **Status**: **Accepted** — operator-ratified 2026-08-15, during the
  generator-only refactor
  ([decision 0013](0013-generator-only-avm-architecture.md)).
  **Amended 2026-08-30** (operator-directed): the firewall narrowing below
  conflated *which* firewall with *whether* to deploy one. The type stays
  bounded to Azure Firewall; deploying one became a required wizard answer
  with no default. See [Amendment](#amendment-2026-08-30--firewall-is-a-question-not-a-constant).
- **Date**: 2026-08-15
- **Deciders**: operator (ratified the capability narrowings and the
  answer-preservation posture, 2026-08-15); recorded by
  `docs-knowledge-curator`
- **Technical depth**: L200 (question-to-consumption mapping; module-level
  capability deltas)

## Context and Problem Statement

The four-pin AVM architecture (decision 0013) does not carry every
capability of the deleted bespoke corpus, but the `site/` wizard's
question set encodes real engagement knowledge — governance posture,
security intent, FinOps structure — that would be lost if the wizard were
cut down to the Terraform surface. The question this record answers: what
happens to each wizard answer now that the emitted architecture changed,
and which bespoke capabilities are deliberately not carried forward?

## Decision

**The wizard keeps its full 15-step question set.** Answers divide into
three consumption classes, mapped exhaustively in
[docs/refactor/COVERAGE.md](../refactor/COVERAGE.md) and enforced in both
directions (token engine fails closed on unknown paths;
`Test-LzSchemaDrift` fails on unfed variables and orphan keys):

1. **Terraform-consumed** — mapped in
   `factory/renderer/variable-map.json` (mapVersion `2.0.0`, target
   schema `2.1.0`). Notably, `deploy_vpn_gateway`
   (`connectivity.vpn.enabled`) and `deploy_expressroute_gateway`
   (`connectivity.expressRoute.enabled`) are **newly consumed** — these
   answers were collected before this refactor but recorded-only.
2. **Broker-consumed** — GitHub settings, identity model, environments
   and approvals, deployed by the bootstrap broker.
3. **Docs / answer-record-only ("recorded-not-deployed")** — Defender
   plans, Sentinel, Key Vault CMK, naming patterns, budgets. The wizard
   warns at the question, render guards G02/G03 warn at render
   (`factory/renderer/public/Test-LzRenderGuards.ps1`), and every answer
   is preserved in the committed `lz-config.json` answer record and the
   generated documentation — never silently dropped.

**Capability narrowings versus the bespoke corpus — all ratified:**

- **Firewall is Azure Firewall only.** The `palo`/`fortinet` NVA options
  are retired (the AVM connectivity patterns deploy Azure Firewall); the
  wizard collects the tier (`connectivity.firewall.azfwTier`), and
  `firewall_enabled` maps `literal:true`. Third-party NVA insertion is
  per-estate work in the generated repository.
  *(The `literal:true` half of this clause is superseded by the
  [2026-08-30 amendment](#amendment-2026-08-30--firewall-is-a-question-not-a-constant);
  the type narrowing stands.)*
- **Workload spoke layers and the sandbox layer are per-estate work** in
  the generated repository, not generator layers — consistent with the
  pre-existing position that tenant-bound work executes per-estate at
  instantiation ([REVIEW.md](../../REVIEW.md) §7, the reference
  [CLASSIFICATION.md](../refactor/CLASSIFICATION.md) cites as
  REVIEW.md:196). Guard G21 refuses configurations selecting layers
  absent from `factory-version.json` `landingZone.layers`.
- **Custom management-group hierarchies require a custom ALZ library
  architecture.** The five `*_management_group_id` placement-target
  variables default to the pinned library's ids (`platform/alz` @
  `2026.04.2`) and are deliberately question-free (`literal:*` in the
  variable map).
- **The bespoke policy definitions are replaced by the ALZ library.** The
  12 hand-authored definitions and 8 assignments are gone; policy surface
  comes from the pinned library via the `alz` provider.

**Capability gains, same refactor:**

- **Virtual WAN topology is fully supported** — previously
  export-blocked in the wizard, now rendered via
  `Azure/avm-ptn-alz-connectivity-virtual-wan/azurerm` and CI-proven by
  the `vwan-config` fixture in `terraform-policy-checks.yml`.
- **VPN and ExpressRoute gateways deploy from answers** (the two
  newly-consumed variables above).

## Consequences

- **Positive**: no engagement knowledge is discarded — a
  recorded-not-deployed answer survives in the answer record and docs,
  and re-enters scope by mapping, not by re-interviewing the client; the
  wizard warns wherever an answer will not deploy, so the gap between
  intent and estate is visible before export; coverage is
  machine-enforced in both directions rather than by review.
- **Negative**: "recorded-not-deployed" is a standing expectation gap to
  manage — [TODO.md](../../TODO.md) item 2.4's scaffold modules are gone,
  so re-opening Defender/Sentinel/CMK now means AVM resource modules or
  per-estate work, not finishing a stub.
- **Follow-ups**: the brownfield answers stay deferred with the
  quarantined tooling ([CLASSIFICATION.md](../refactor/CLASSIFICATION.md)
  UNRESOLVED-2); naming answers validate and document but resource names
  inside AVM modules follow the modules' own conventions.

---

## Amendment 2026-08-30 — firewall is a question, not a constant

**What was wrong.** The clause above reads as though "always deploy a
firewall" were a property of the AVM connectivity patterns. It is not. Both
emitted topologies thread the boolean straight into the module —
`platform-connectivity/main.tf.tmpl`:

```hcl
firewall                              = var.firewall_enabled
firewall_policy                       = var.firewall_enabled
bastion                               = var.deploy_bastion
```

The module accepts `false` for `firewall` exactly as it does for `bastion`,
which sits one line below and *was* a real wizard answer all along. What
actually forced the firewall on was smaller and less deliberate: the
renderer never emitted a `firewall_enabled` line into
`terraform.auto.tfvars`, so `default = true` in the layer's `variables.tf`
decided it. `variable-map.json`'s `literal:true` was documentation of that
omission, not a constraint anyone had chosen.

The consequence was a silent one. The wizard asked which **tier** and never
**whether**, so a client answering every question truthfully still got an
Azure Firewall — roughly USD 900–950 per month per hub for Standard, double
that for Premium — with no question anywhere in the wizard that could have
declined it, and no error to say so.

**What changed.**

- `connectivity.firewall.enabled` is a new schema key, `required`, with
  **no default**. Same for `connectivity.bastion.enabled`, which previously
  defaulted to `true` at roughly USD 140 per month per hub.
- The wizard asks both as explicit yes/no questions whose initial state is
  unanswered, and refuses to export until each is answered. A "no" on the
  firewall exports cleanly and raises a warning that platform egress is
  uninspected — a supported answer for an estate whose workloads do not
  route through the hub, not a mistake.
- `firewall_enabled` now maps to the answer rather than to `literal:true`,
  and is emitted into the connectivity layer's tfvars.
- `firewall_enabled` and `deploy_bastion` lose their `variables.tf`
  defaults. The renderer always emits both, so an absent value means a
  hand-edited tfvars, and that should fail loudly rather than quietly spend.

**What did not change.** The type narrowing stands: Azure Firewall is the
only firewall this generator composes, and a third-party NVA remains
per-estate work in the generated repository. Setting the topology to `none`
remains the separate, supported way to emit no platform networking at all.

**The general lesson, which outlives this clause.** An answer the wizard
collects but never emits does not fail — it silently takes the template
default, and every gate stays green. That is the same shape as
`azure.managementGroups.customHierarchy` and
`governance.policyBaseline.enforcementMode`. The structural fix belongs with
those, not here.
