# Decision 0019 — State storage: hardened public day-0 posture, private endpoint as a gated stage-2 overlay

- **Status**: **Accepted** — 2026-08-17. Planned with the
  `azure-platform-architect` capability (WAF-validated) after the operator
  asked whether the broker should regain the deleted backend-bootstrap's
  private-endpoint option ("plan it out … you have access to azure and avm
  as well as waf agents").
- **Date**: 2026-08-17
- **Deciders**: operator (posed the question and the constraint set);
  design validated against the Azure Well-Architected Framework
- **Technical depth**: L300 (storage network access model, runner
  reachability, Terraform state-ownership boundaries)

## Context and Problem Statement

The deleted `terraform/backend-bootstrap` (bespoke corpus) supported an
optional private endpoint for the Terraform state storage account. The
broker's replacement (`Set-LzAzurermBackend`) created the account with GRS,
TLS 1.2, no public blob access, and shared keys off — but no
private-endpoint option (CLASSIFICATION.md UNRESOLVED-1). Should it regain
one?

Three facts shape the answer:

1. **The emitted pipeline runs on GitHub-hosted runners** (guard G05:
   self-hosted is not supported in v1). A private-only state account is
   unreachable from GitHub-hosted runners — the pipeline would lock itself
   out of its own state.
2. **An IP allowlist is not a middle ground.** Azure Storage network rules
   ignore public IP rules for traffic originating in the same region as the
   account, which is exactly where GitHub-hosted runners frequently are; and
   the 400-rule cap cannot express GitHub's published ranges. An allowlist
   would be a null-op or theatre.
3. **Terraform must never manage its own state account.** A bad plan against
   the account that stores the state being planned is a self-lockout (or
   self-destruction) class of failure.

## Decision

**Day 0 (broker-owned, always):** the state account keeps its public
endpoint with Entra-only auth, hardened in every dimension that does not
break runner reachability:

- `Standard_GZRS` (zone- and geo-redundant), falling back to `Standard_GRS`
  where the region has no zones;
- HTTPS-only, TLS 1.2 floor, no public blob access, shared keys off
  (contract #3), cross-tenant replication off;
- infrastructure encryption on (create-time-only setting — applied on
  creation, never retro-fitted);
- blob versioning plus 30-day blob and container soft delete: corrupted or
  deleted state is a recoverable event;
- a `CanNotDelete` lock on the state resource group;
- **no WORM/immutability** — Terraform's blob-lease locking writes the state
  blob in place, and an immutability policy breaks it;
- **no IP allowlist** — see fact 2 above.

**Stage 2 (estate-owned, opt-in):** `backend.azurerm.privateEndpoint.enabled`
emits a `state-hardening` Terraform layer plus a `state-access-flip`
workflow into the generated repository:

- the layer creates a private endpoint (into a hub subnet) and its
  `privatelink.blob.core.windows.net` zone group; the storage account itself
  is a **data source** — the layer never manages it (fact 3);
- the public-access flip is a separate, human-gated `workflow_dispatch`
  workflow (management environment, confirmation input, requires an
  Approved endpoint before `disable-public`, verifies data-plane
  reachability after, and keeps `enable-public` as the reviewed break-glass
  reversal);
- **guard G27** blocks the flag unless the configuration has the hub-spoke
  topology, centralized private DNS in the hub, and self-hosted runners —
  and self-hosted runners are themselves blocked by G05 in v1, so stage 2 is
  currently declared but unreachable by construction. The wizard shows the
  option disabled with this explanation.

## Consequences

- The day-0 posture upgrade is unconditional and invisible to
  configurations: no schema surface, no new questions.
- Promotion wire: estate-side diagnostics of the state account to the
  management Log Analytics workspace remains per-estate work (ADR 0017
  class), not factory architecture.
- When self-hosted runner support lands (G05 lifts), stage 2 becomes
  reachable with no further schema change.
- Closes CLASSIFICATION.md UNRESOLVED-1.
