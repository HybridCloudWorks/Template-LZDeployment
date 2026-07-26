# Discovery Engine — Phase 0

Read-only inventory and readiness assessment for the Azure Landing Zone Factory.
Run this **before** the bootstrap broker, against any tenant, including production.

> **Nothing is created, modified, or deleted.** Every command issued is a list or
> get. `Assert-LzReadOnly` structurally rejects mutating verbs before execution,
> so a later edit cannot quietly turn a probe into a write.

---

## Quick start

```bash
pwsh ./factory/discovery/Invoke-Discovery.ps1 -ConfigPath ./generated-output/contoso/lz-config.json
```

Two artifacts are written beside the configuration:

| File | Audience |
|---|---|
| `tenant-readiness-report.md` | The human gate. Read this before bootstrapping. |
| `discovery-inventory.json` | Machine-readable. Consumed by later factory stages (brownfield import generation, the broker). |

Exit code is `0` unless `-FailOnNotReady` is passed, in which case a failed
readiness check exits `1` — intended for CI.

---

## The rule this engine exists to enforce

**An inaccessible scope must never look like an empty one.**

Those two results lead to opposite decisions. "No management groups exist" says a
greenfield build is safe. "I was not allowed to enumerate management groups" says
the operator lacks the access the deployment will need — and possibly that a
hierarchy is already there, unseen.

Every probe therefore resolves to one of five states, and `Empty` and `Forbidden`
never collapse into each other:

| Status | Meaning | Trustworthy? |
|---|---|---|
| `Ok` | Ran, found items. | Yes |
| `Empty` | Ran, the resource genuinely does not exist. | Yes |
| `Forbidden` | Access denied. **Not** the same as `Empty`. | **No** |
| `Unavailable` | Could not run — CLI missing, not signed in, token expired. | **No** |
| `Error` | Unexpected failure. Treated as unknown. | **No** |

The `Conclusive` field on each result is `true` only for `Ok` and `Empty`. The
report renders blocked probes explicitly and states that the inventory is
incomplete rather than presenting a partial list as a complete one.

This implements control **BR2** in [`docs/factory/FACTORY-DESIGN.md`](../../docs/factory/FACTORY-DESIGN.md).

---

## Readiness checks

Ten capability questions, each answered by **reading effective permissions** —
never by attempting a mutation and rolling it back. A rollback that fails halfway
leaves debris in a tenant the operator may not own.

Azure capabilities are proven via `Microsoft.Authorization/permissions`, which
returns the caller's `actions`/`notActions` at a scope; entitlement is then
evaluated with normal RBAC wildcard semantics. Entra capabilities are proven via
directory role membership.

| ID | Check | Method |
|---|---|---|
| R01 | Create app registrations | Entra directory role membership |
| R02 | Create federated credentials | Same role, plus the 20-per-app ceiling |
| R03 | Create management groups | `Microsoft.Management/managementGroups/write` |
| R04 | Subscription availability | Configured IDs vs. accessible IDs |
| R05 | Create and assign policies | `Microsoft.Authorization/policy*/write` |
| R06 | Assign RBAC roles | `Microsoft.Authorization/roleAssignments/write` |
| R07 | Configure diagnostics | `Microsoft.Insights/diagnosticSettings/write` |
| R08 | Deploy networking | `Microsoft.Network/virtualNetworks/write` + address-space collision scan |
| R09 | GitHub access | Auth, ownership-model match, available control set |
| R10 | Terraform backend access | HCP org reachability and RUM headroom, or state account exposure |

### Pass / Warning / Fail

- **Pass** — capability confirmed present.
- **Warning** — could not be confirmed, or present with a caveat. A judgement call.
- **Fail** — confirmed absent. Bootstrap will not succeed.

An unreadable permission set yields **Warning**, never Pass. *"I could not check"*
and *"this is fine"* must never render identically.

---

## What each domain probes

**GitHub** — authenticated identity, token scopes, owner account type and plan,
organization settings, Actions policy and allow-list, self-hosted runners,
existing repositories, and the target repo's current branch protection and
environments.

The derived capability assessment is the important output: a Free personal
account cannot have environments or branch protection on a private repository,
which silently removes every approval gate the design depends on. That is named
explicitly rather than skipped (risk **GH1**).

**Entra** — signed-in context and tenant match, directory roles, app
registrations, federated credentials (with the per-app ceiling), service
principals, managed identities, administrative units, and Conditional Access
policies.

CA policies are surfaced because a policy requiring a compliant device can break
workload identity federation at the *first CI run* — long after bootstrap
reported success.

**Azure** — accessible subscriptions, configured-subscription reachability,
management group hierarchy, virtual networks, resource groups, Log Analytics
workspaces, key vaults, policy assignments and custom definitions, the operator's
role assignments, Defender plans, and Sentinel workspaces.

Two derived outputs: **address-space collision** detection against the planned
hub/spoke CIDRs, and an **existing landing zone** heuristic that challenges a
`greenfield` declaration when the tenant clearly is not empty.

**Terraform** — CLI version, and then either HCP Terraform (credentials,
organizations, workspaces, variable sets, policy sets, and current managed-resource
count against the **500-resource free-tier cap**) or the `azurerm` state storage
account (existence, and whether it is publicly reachable).

---

## Platform notes

Several implementation choices exist because of a live run on Windows, and
reverting them will reintroduce real bugs:

- **Graph is called via `Invoke-RestMethod`, not `az rest`.** A URL containing
  `&` is not quoted by PowerShell, and the `az.cmd` shim hands it to `cmd`, which
  treats `&` as a command separator. This produced `'$top' is not recognized as an
  internal or external command`.
- **OData filters are percent-encoded into the URL.** `startswith(displayName,'x')`
  as a command-line argument gives `cmd` unbalanced parentheses, producing
  `--query was unexpected at this time`.
- **CIDR arithmetic uses `int64`.** PowerShell's `-bnot` on a `uint32` yields a
  signed value, which throws converting the broadcast address.
- **Resource Graph queries are guarded by an extension check**, so a missing
  `resource-graph` extension produces an actionable remediation instead of a
  dynamic-install warning.

---

## Usage

```powershell
Import-Module ./factory/discovery/LZFactory.Discovery.psd1

# Full run
Invoke-LzDiscovery -ConfigPath ./generated-output/contoso/lz-config.json

# One domain
Get-LzAzureInventory -SubscriptionIds @('...') -ManagementGroupRootId 'mg-contoso' `
                     -PlannedAddressSpaces @('10.0.0.0/16','10.1.0.0/16')

# Skip domains you are not signed in to
Invoke-LzDiscovery -ConfigPath ./lz-config.json -SkipDomain GitHub,Terraform
```

### Prerequisites

| Tool | Needed for | Sign-in |
|---|---|---|
| `az` ≥ 2.69 | Entra + Azure | `az login --tenant <id>` |
| `gh` ≥ 2.67 | GitHub | `gh auth login` |
| `terraform` ≥ 1.9 | Backend | `terraform login` (HCP only) |
| `az extension add --name resource-graph` | Tenant-wide inventory | — |

A domain you are not signed in to reports `Unavailable` with remediation; the
other domains still run. Partial discovery is expected and handled.

---

## Secret handling

Discovery has no legitimate need to emit a credential, and its output is routinely
pasted into tickets and chat. `Protect-LzSecretText` redacts JWTs, GitHub tokens,
HCP tokens, and `client_secret`-style assignments from everything written to disk
— applied on the way out rather than trusting every upstream CLI never to echo a
token in an error message.

The HCP Terraform token is read from `~/.terraform.d/credentials.tfrc.json` and
held in memory only. Graph tokens are acquired per-session and never persisted.

---

## Status

Factory stage 4 of 13. The Stage 9 bootstrap broker and Stage 11 brownfield
generator consume `discovery-inventory.json`; the latter requires every
supported Azure probe to be conclusive and pins classifications to the
inventory SHA-256. This engine is also useful standalone as a pre-flight
assessment.
