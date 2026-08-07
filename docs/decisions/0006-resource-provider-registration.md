# Decision 0006 — Resource-provider registration strategy under azurerm 5.0

- **Status**: Accepted — operator-ratified in-session 2026-08-07: **Option A
  (broker-time registration) complemented by Option B's read-only PF-D
  preflight finding; Option C ratified against, even as belt-and-braces.**
- **Date**: 2026-08-06 (authored); 2026-08-07 (ratified)
- **Deciders**: operator (ratified 2026-08-07); `azure-platform-architect`
  (authored the options paper)
- **Technical depth**: L300 (implementation)

## Context and Problem Statement

azurerm `~> 5.0` is permanent for both trees — operator-ratified 2026-08-06
("we are staying on azurerm 5.0"), enforced by
`factory/ci/Test-ProviderConstraints.ps1` — so its one open consequence cannot
be sidestepped by a rollback. 5.0 changes the provider default
`resource_provider_registrations` from `legacy` to `none` (provider docs,
verified 2026-08-06: allowed values `core | extended | all | legacy | none`;
`none` means "the provider will not attempt to register any resource
providers"; the companion list argument `resource_providers_to_register` "can
be used in combination with the `resource_provider_registrations` property").
No provider block in either tree sets either argument, so every generated root
runs at the `none` default.

Consequently the **first `terraform apply` into any fresh subscription fails**
on the first resource whose provider namespace has never been registered
there. The error surfaces mid-apply, per resource, shaped like:

```
Error: creating Virtual Network (Subscription: "…", Resource Group: "rg-…", Name: "vnet-…"):
unexpected status 409 (409 Conflict) with error: MissingSubscriptionRegistration:
The subscription is not registered to use namespace 'Microsoft.Network'.
See https://aka.ms/rps-not-found for how to register subscriptions.
```

Every engagement provisions into fresh subscriptions (management,
connectivity, workload prod/non-prod, optionally sandbox — see
[decision 0002](0002-minimal-identity-estate.md) for the identity estate), so
this gates the entire go-live chain: nothing after the first apply can happen
until registration happens somewhere, on some identity.

The axis the choice turns on (per REVIEW.md §10) is **which identity holds
registration rights, and where that privilege placement is least surprising**.
Registration is a subscription-scoped, idempotent, one-time write requiring
`Microsoft.<Namespace>/register/action` on the target subscription. Owner and
Contributor include it (via `*`); **Reader does not**. Microsoft's documented
minimal grant is a custom role carrying `*/register/action`. Two repo
contracts constrain the placement:

- **Contract #2 (OIDC identity split)**: the plan SP is Reader-only and, in
  REVIEW.md's own framing, "should never attempt a registration". The apply SP
  holds Contributor per workload subscription — but the **bootstrap**
  environment identity holds only Management Group Contributor + Resource
  Policy Contributor at the MG root, not subscription Contributor, so it
  cannot register.
- **[Decision 0004](0004-factory-copy-is-a-disposable-installer.md)**: the
  broker runs once, on the client's machine, under the **client's own `az`
  session** — the same session that already creates service principals,
  federated credentials, and MG-root role assignments, and therefore already
  holds Owner-class rights that include `*/register/action` on every target
  subscription.

### Namespaces the corpus needs

Derived from the distinct `azurerm_*` resource types in
`factory/templates/terraform/` (37 types, enumerated 2026-08-06). The exact
per-layer list must be pinned at implementation time against the rendered
tree, since rendering is config-conditional:

| Namespace | Pulled in by |
| --- | --- |
| `Microsoft.Network` | VNets, subnets, NSGs, firewall, public IPs, route tables, peerings, private endpoints, flow logs |
| `Microsoft.Storage` | state/diagnostics storage accounts |
| `Microsoft.OperationalInsights` | Log Analytics workspace |
| `Microsoft.Insights` | App Insights, diagnostic settings, action groups, metric alerts, scheduled-query rules |
| `Microsoft.Automation` | automation account, runbooks, schedules (sandbox expiry) |
| `Microsoft.RecoveryServices` | Recovery Services vault |
| `Microsoft.DataProtection` | backup vault |
| `Microsoft.KeyVault` | key vault |
| `Microsoft.Security` | Defender contacts/settings/pricing/workspace |
| `Microsoft.PolicyInsights` | policy compliance surfaces |
| `Microsoft.Management` | MG–subscription associations |

(`Microsoft.Authorization` — role assignments, policy definitions — is
registered by default in every subscription and needs no action.)

## Considered Options

The three candidates from REVIEW.md §10, costed on: which identity needs
`register/action`, blast radius, when it runs, failure visibility, and
ongoing maintenance.

### Option A — broker-time registration

`factory/bootstrap/LZFactory.Bootstrap.psm1` registers the namespace list in
every target subscription during bootstrap (`az provider register`, then polls
`registrationState == Registered`), recording the outcome per subscription in
`bootstrap-audit.json`.

- **Identity needing `register/action`**: the client's interactive `az`
  session — which under decision 0004 already holds Owner-class rights on
  these subscriptions (it creates MG-root role assignments). **Zero new
  grants; no standing identity gains a privilege.** This is the
  least-surprising placement: the most privileged principal in the whole
  motion is also the shortest-lived, and it exists only during bootstrap.
- **Blast radius**: none beyond the engagement's own subscriptions, and the
  privilege evaporates when the client's session ends. The CI identities in
  the generated repo remain exactly as contract #2 defines them.
- **When it runs**: once per engagement, before any Terraform runs — the
  failure mode is eliminated rather than detected.
- **Failure visibility**: interactive, at the console, while the client is
  present — broker events plus the audit file. Registration is asynchronous
  (typically seconds to a few minutes per namespace); the broker must poll or
  record `pending`, which is bounded, not open-ended.
- **Ongoing maintenance**: the namespace list lives in PowerShell, away from
  the Terraform that needs it — a new module adding a resource type must
  remember to extend the broker list (mitigable with a Factory CI check that
  diffs corpus resource types against the broker list). Subscriptions added
  *after* the factory copy is deleted get nothing — but adding a subscription
  post-engagement is outside this factory's motion by definition
  (decision 0004).

### Option B — preflight detection (`Test-LzFirstApplyPreflight` PF-D)

Add a fourth check family to the existing advisory preflight: `az provider
list` per target subscription (a read — Reader suffices), flag unregistered
required namespaces as WARN findings with an `az provider register`
remediation, persist in the `preflight` array of `bootstrap-audit.json`.

- **Identity needing `register/action`**: none for the check itself; the
  *remediation* privilege lands ad hoc on whoever acts on the finding —
  unplaced by design.
- **Blast radius**: zero — the check is read-only and fits the preflight's
  existing "detects and explains; never edits, never blocks" contract.
- **When it runs**: at bootstrap, early and loud — but **detection is not
  remediation**. Alone, the first apply still fails; this option only
  converts a mid-apply 409 into a pre-warned mid-apply 409.
- **Failure visibility**: best of the three — a named finding with an exact
  remediation string, before any Terraform runs.
- **Ongoing maintenance**: same list-drift exposure as Option A.
- **Verdict as a standalone**: insufficient. Viable only as a complement to A
  or C.

### Option C — `resource_providers_to_register` in the generated provider blocks

Each rendered layer's `provider "azurerm"` block carries
`resource_providers_to_register = [ … ]` with that layer's namespaces
(combined with the `none` default, as the provider docs permit).

- **Identity needing `register/action`**: **the CI identities** — and this is
  where the option breaks on contract #2. The provider attempts registration
  at provider initialization, which happens during **plan** as well as apply.
  On a fresh subscription the first plan runs *before* the first apply (the
  plan gate) and authenticates as the Reader plan SP, which hard-fails:
  `Cannot register provider: Microsoft.Network … does not have authorization
  to perform action 'Microsoft.Network/register/action'
  (AuthorizationFailed)`. Fixing that means granting the read-only plan
  identity a subscription-mutating right (`*/register/action`), directly
  violating the split — or accepting a red first plan per subscription, which
  defeats the gate. The bootstrap-environment identity (global layer) holds
  no subscription Contributor at all, so `global`'s provider block must be
  exempted regardless.
- **Blast radius**: registration rights become **standing** privileges on
  long-lived OIDC identities in the generated repo, versus a one-shot
  interactive session in Option A.
- **When it runs**: on every provider init — self-healing for future fresh
  subscriptions (the one scenario A cannot cover), and a cheap no-op read once
  registered.
- **Failure visibility**: a red pipeline run — later and less actionable than
  either A or B.
- **Ongoing maintenance**: best co-location — the list lives beside the
  Terraform that needs it and travels with the generated repo. This is the
  option's genuine strength, and it is outweighed by the privilege-placement
  conflict.

## Decision

**Recommendation — explicitly a recommendation, not a decision; ratification
is the operator's call:**

Chosen option would be: **Option A (broker-time registration), complemented by
Option B's read-only verification as a PF-D preflight finding**, because the
client's bootstrap session is the only identity in the motion that already
holds `register/action` on every target subscription, so registration lands on
the most privileged, shortest-lived principal with zero new grants — while
Options B (alone) fixes nothing and C forces registration rights onto the CI
identities in violation of the OIDC privilege split.

Option C is recommended **against** even as a belt-and-braces addition: any
value of `resource_providers_to_register` makes the Reader plan SP attempt a
write on a fresh subscription.

## Consequences

*(Of the recommended option, if ratified.)*

- **Positive**: the failure mode is eliminated before Terraform ever runs; no
  contract #2 change; no new role assignments anywhere; the generated provider
  blocks stay at the untouched 5.0 default (`none`), which is exactly the
  posture REVIEW.md §10 wants for the plan identity; failures surface
  interactively while the client is at the console (decision 0004's model),
  with an audit trail in `bootstrap-audit.json`.
- **Negative**: the namespace list is maintained in the broker, decoupled from
  the Terraform corpus — drift risk when a module adds a resource type; the
  broker gains an asynchronous polling step (bounded, minutes); a subscription
  added after engagement disposal must be registered manually (documented
  limitation, consistent with the disposable-installer model).
- **Follow-ups** (implementation work, only after ratification):
  1. Broker: registration step + `registrationState` polling + audit entries,
     idempotent like every other broker mutation.
  2. Preflight: PF-D findings (read-only verification per target
     subscription), following the PF-A..C pattern.
  3. Factory CI: a drift check comparing the corpus's `azurerm_*` resource
     types against the broker's namespace list, so the maintenance risk in
     the Negative column fails loudly instead of at a client site.
  4. Optional clarity: render `resource_provider_registrations = "none"`
     explicitly in the generated provider blocks so the posture is stated
     rather than inherited.
  5. Curator pass: reconcile REVIEW.md §10, TODO.md, and CHANGELOG.md pointers
     to this record (deliberately not done in the authoring pass).
