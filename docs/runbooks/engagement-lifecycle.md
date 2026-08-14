# Runbook — Engagement Lifecycle Hygiene (Phase 7)

**Scope**: what happens *between* engagements — upgrade channels, provenance,
and operator-workstation isolation. Model:
[decision 0004](../decisions/0004-factory-copy-is-a-disposable-installer.md).
Disposal itself: [engagement-disposal.md](engagement-disposal.md).

Artifact chain per engagement: **upstream repo** (the factory) → **client
copy** (private, per [decision 0001](../decisions/0001-private-copy-over-public-fork.md))
→ **local clone** (disposable) → **generated customer repo** (long-lived).

---

## 1. Upgrade channels

There are exactly two, and they are different mechanisms:

### Client copy ← upstream factory

The client copy is a private copy, not a fork, so GitHub's fork-sync is
unavailable. Sync by **mirror push** from a fresh upstream clone (the same
mechanic `Initialize-ClientFork.ps1 -CreatePrivateCopy` uses), or retire and
**re-copy**. Nothing needs re-hardening after either: the client copy is
disposable and never hardened (decisions 0004/0007) — only its **private**
visibility matters, which the script's read-back reports.

### Customer repo ← factory corpus

The **supported regeneration/upgrade path** for a generated customer repo is
`scaffold-copy.ps1` existing-repo mode: re-render from the archived
`lz-config.json`, point `LZ_SCAFFOLD_TARGET` at a clean clone of the customer
repo's default branch, and the builder pushes the update to
`LZ_SCAFFOLD_BRANCH` and opens a **draft PR** — it never pushes the protected
default branch. The customer's own required checks and reviews gate the
merge. Do not hand-edit generated files in the customer repo to apply a corpus
fix; regenerate.

## 2. Engagement provenance

Every wizard export stamps versions: `deployment-metadata.json` records the
factory/schema versions of the export, and the generated repo carries the
factory version from `factory-version.json` (also stamped into the generated
`USER-CHECKLIST.md` header).

Keep an **operator-side record of customer → factory version per export**,
so that
when a corpus defect is found, the affected engagements can be enumerated and
each customer repo upgraded through the draft-PR channel above. Record, at
minimum: customer, export date, factory version, schema version, and the
archive location of the engagement's `lz-config.json`.

## 3. Operator workstation isolation

A session or artifact from customer A must never be able to touch customer B:

- **One clone per customer.** Never reuse a clone or share
  `generated-output/` across engagements.
- **End sessions between engagements**: `az account clear` and
  `gh auth logout` (and `terraform logout` when HCP Terraform was used) —
  the same session-ending steps disposal performs.
- Unset `TFE_TOKEN` and all `LZ_*` variables before starting the next
  engagement; stale `LZ_*` paths silently point new tooling at the previous
  customer's artifacts.
