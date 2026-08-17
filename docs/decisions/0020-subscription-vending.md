# Decision 0020 — Subscription vending: the wizard plans names, a script creates and patches back

- **Status**: **Accepted** — operator-directed 2026-08-17 ("because of the
  naming convention, let's assume the wizard will provide the names itself
  and the ps script to create them as well, then that script will also
  create the file needed to continue with the new sub IDs"; billing answer:
  "mixed").
- **Date**: 2026-08-17
- **Deciders**: operator (directed the mechanism and the mixed-billing
  requirement)
- **Technical depth**: L200 (billing-scope resolution, alias API, config
  contract)

## Context and Problem Statement

The wizard previously assumed the landing-zone subscriptions already
existed: the client created them in the portal and pasted the IDs. With
brownfield redefined as exclude-and-create (decision
[0018](0018-brownfield-exclude-and-create.md)), *new* subscriptions are the
normal case in every engagement, and hand-creating them breaks the
naming convention the wizard already owns. Where do the new subscriptions
come from?

## Decision

1. **The wizard plans names.** Schema 2.2.0 adds
   `azure.subscriptions.mode` (`create` | `existing`, default `create`).
   In create mode the wizard derives display names from the naming
   convention (`sub-<shortName>-management|connectivity|workload-prod`,
   plus opt-in `identity`, `workload-nonprod`, `sandbox`) into
   `azure.subscriptions.plannedNames`, and exports the config with the ID
   slots empty. In existing mode the IDs are pasted as before (the required
   three tighten back to GUIDs via the schema's `allOf`).
2. **`scripts/New-LzSubscriptions.ps1` creates them and patches the config.**
   Plan-first (`-Apply` to mutate), idempotent (stable alias names), and
   **mixed-billing aware**: it enumerates every billing account visible to
   the operator's `az` session, offers every usable scope — EA enrollment
   accounts and MCA invoice sections alike — and creates each subscription
   via `az account alias create --billing-scope`. It then writes the new
   IDs into `lz-config.json` (backup beside it), fills
   `backend.azurerm.subscriptionId` from the management subscription when
   empty, and re-validates the file against the schema.
3. **Manual fallback for non-programmatic agreements.** CSP and
   pay-as-you-go cannot create subscriptions through the alias API; the
   script detects the absence of a usable scope and `-Manual` collects
   portal-created IDs with the same patch-back and re-validation.
4. **Guard G25** refuses to render a create-mode configuration whose planned
   slots still carry no IDs, naming the script as the missing step — an
   unfilled create-mode config can never produce a repository.
5. **Minimum estate is three subscriptions** (management, connectivity,
   workload-prod), not six: the optional slots stay opt-in checkboxes.

## Consequences

- `NEXT-STEPS.md` gains a vending step between authentication and
  discovery, numbered dynamically.
- Guard G26 (decision 0018) cross-checks vended IDs against the brownfield
  exclusion list; the script enforces the same rule at patch time.
- The subscriptions are created bare: management groups, RBAC, and policy
  land later through the normal layer applies (`avm-ptn-alz`'s
  `subscription_placement` does the placement).
- Renaming or re-parenting subscriptions after creation is out of scope for
  the script; it never modifies an existing subscription.
