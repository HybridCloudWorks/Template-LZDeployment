# Plan — Corpus ↔ Live Reconciliation (EXECUTED — stub)

**Status**: **EXECUTED 2026-08-02**; all seven work packages landed and every
follow-on decision has since been resolved. This file was reduced to a stub on
2026-08-07 (root-docs consolidation): no open action items remain here, and
the execution record lives in [CHANGELOG.md](../../CHANGELOG.md) ("Corpus↔live
reconciliation executed — WP1–WP7", 2026-08-02).

Where the surviving substance lives:

- **WP4 design rationale** (management-baseline promotion, the
  `wire_management_workspace` gated remote-state read):
  [decision 0003](../decisions/0003-management-baseline-promotion.md).
- **Finding (b)** (action-pin drift was checker-invisible): closed by the
  canonical-SHA registry in `factory/ci/Test-ActionPins.ps1`, which cites this
  plan.
- **Regeneration risk** (hub-network destroy/recreate on older generated
  repos): documented in the corpus `UPGRADE-GUIDE.md.tmpl`; route affected
  repos through the Stage 11 brownfield path.

Deviations from the plan as written, resolved and final:

- the `azfw_tier` "Basic" item was resolved by **narrowing the schema enum**
  (Basic removed, `$comment` rationale, wizard import guard) instead of
  widening the module — Basic needs a management subnet/NIC the hub-network
  module does not provision; the WP6 live backport was reverted;
- the management-baseline alert rename ships with a **corpus-only
  `moved.tf`** — resolved 2026-08-06 as a **PERMANENT** divergence that must
  not be mirrored to live (live never held state under the old address);
- `terraform/compose-package/` was deleted along with the two dead workflows
  that were its only consumers.

The pre-execution audit body (module inventory, hub-network detail, live-stack
and workflow findings) was removed with the stub; recover it from git history
at tag/commit `752481a` or earlier if ever needed.
