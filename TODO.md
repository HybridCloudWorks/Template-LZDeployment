# TODO — HCW Landing Zone Factory

> **File contract (operator-defined 2026-08-07, supersedes the 2026-08-06
> contract).** This file holds **ALL action items found repo-wide**, triaged in
> chronological, logical order, **in phases**, so it can serve as a proper
> handoff. Items blocked on the operator or an external system appear here too
> — each names its gate and references its **[REVIEW.md](REVIEW.md)** entry,
> the blocker registry that records who can unblock it and the next concrete
> action. Completed work is recorded in [CHANGELOG.md](CHANGELOG.md)
> (new-features changelog). Root markdown is limited to four files: README.md,
> CHANGELOG.md, REVIEW.md, TODO.md.

**Last Updated**: August 14, 2026
**Status**: 🟢 Phases 1–2 closed through PR #92 except 2.16 (five subnets
remain, gated on client DNS design + firewall choice) and 2.4/2.5/2.6
(operator-gated — REVIEW.md §14/§16/§13); Phase 3 gated on the authenticated
toolchain (§7) and wiki write access (§15); Phase 4 deferred (go-live not
opened); Phase 5 release-time
**Operator activities & stage checklists**: [docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)
**External tracking**: [GitHub Issues](https://github.com/HybridCloudWorks/Template-LZDeployment/issues)

---

## What this repo is

The **Landing Zone Factory** (see [README.md](README.md)): a disposable
installer that renders a self-contained, per-customer landing-zone repository
from `lz-config.json` (`site/` wizard → discovery → broker → render →
validate → scaffold). The client runs it once, on their own machine, and the
copy is deleted; the **generated** repository is the deliverable
([decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)).
The legacy self-deploying path (`terraform/live/` + numbered workflows) is
retained as the Stage 13 dogfood instance.

---

## Phase 1 — Startable engineering fixes

**Closed 2026-08-07 (PR #77)** — all three items (1.1 template-corpus
V07/V08 cleanup, 1.2 Linux scaffold hidden-file crash, 1.3 enum/`contains`
drift-checker gap) shipped, including the live-tree mirror of the 1.1
cleanup. The record is in [CHANGELOG.md](CHANGELOG.md). Two notes survive
the closure:

- Item 1.1's validation criterion — `validate-render.ps1 -Strict` passing
  V07/V08 with **no skips recorded** — is not yet confirmed: tflint/tfsec
  were unavailable in the sandbox. The confirmation run is folded into
  item 3.1.
- Item 1.3 was partially stale when picked up: the production checker gap
  had already been closed by 435845e (#69, 2026-08-05) after the item was
  written (2026-08-02), and the 2026-08-06 consolidation missed it — the
  deliverable became the missing end-to-end proof. When work lands, close
  the TODO item in the same change.

The next startable work is gated: see Phases 2–5.

---

## Phase 2 — Implementation gated on operator ratifications

Implementation is straightforward once the named decision is ratified. The
decision itself — who can make it and what has to be chosen — is recorded in
the referenced REVIEW.md entry; do not start the work before the gate lifts.

### 2.1 Implement the resource-provider registration strategy (decision 0006) — CLOSED

Closed 2026-08-07: the gate lifted when the operator ratified
[decision 0006](docs/decisions/0006-resource-provider-registration.md)
in-session (Option A broker-time registration + Option B's PF-D preflight
finding; Option C ratified against). Shipped: broker registration step with
bounded polling and per-subscription per-namespace audit entries, read-only
PF-D findings, the Factory CI "Resource provider coverage" corpus↔broker
drift check, and explicit `resource_provider_registrations = "none"` in the
rendered (and mirrored live) provider blocks. **Criterion split**: the
`Test-Bootstrap.ps1`-green criterion is verified (85/0); the "first apply
into a fresh subscription no longer fails" criterion is estate-gated and
folds into item 3.1's authenticated-toolchain run, the same way item 1.1's
strict-validation residual did. Item number retained so cross-references
stay stable; record in [CHANGELOG.md](CHANGELOG.md).

### 2.2 Disposition of `scripts/Initialize-ClientFork.ps1` — CLOSED

Closed 2026-08-07: the gate lifted when the operator ratified
[decision 0007](docs/decisions/0007-retire-client-copy-hardening.md)
in-session (retire the hardening stages; keep `-CreatePrivateCopy` as the
documented private-copy mechanic; retargeting at the generated repo ruled
out — the broker is the sole hardening owner there). Shipped: the script
stripped to the private-copy mechanic with visibility read-back, its
comment-based help rewritten to the surviving purpose, the retired
parameters (`-Branch`, `-RequiredApprovals`, `-RequiredChecks`,
`-EnforceAdmins`) removed, and every live instruction that pointed at the
hardening stages updated (README, CLAUDE.md, USER-CHECKLIST, REVIEW.md §2,
the Stage 13 runbook's Gate 2/Gate 5/troubleshooting rows, the
engagement-lifecycle runbook). Both validation criteria verified:
`grep -rn Initialize-ClientFork` shows no stale live instructions
(decision-record and CHANGELOG history retained as history), and
`Get-Help` parses the rewritten help cleanly. Item number retained so
cross-references stay stable; record in [CHANGELOG.md](CHANGELOG.md).

### 2.3 Wire `nsg-flow-logs` into a live stack — CLOSED

Closed 2026-08-09: the gate lifted when the operator ratified
[decision 0009](docs/decisions/0009-nsg-flow-log-scope-and-workspace-target.md)
in-session 2026-08-08 as recommended (**A2** all three spoke NSGs, **B1** the
existing `management-baseline` workspace, **C2** hosted in the workload
layers). Shipped, both trees at parity: `spoke-network`'s `nsg_ids` map output
keyed `app`/`data`/`pe`; `management-baseline`'s
`log_analytics_workspace_guid` and `log_analytics_workspace_location` (the
pre-existing `log_analytics_workspace_id` left as the full ARM ID); the
`count`-gated `wire_management_workspace` remote-state read extended into the
live connectivity layer with a `management_workspace` re-export, so
`workloads-prod` feeds the module from the connectivity state it already reads
rather than adding a second read (decision 0009 Q4 — in scope); two
`nsg-flow-logs` instances in `workloads-prod`, one per region, each
`count`-gated on `enable_nsg_flow_logs` **defaulting to `false`**; the
renderer mapping for `security.nsgFlowLogs.{retentionDays,trafficAnalytics}`,
with `enable_nsg_flow_logs` mapped `literal:false` so the wizard's pre-checked
box cannot turn a volume-driven meter on for a client who never touched it
(Q3); and the fabricated `estimated_monthly_cost_usd` output deleted in favour
of a documented per-GB formula in the module README (Q5).
**Criterion split**: the `terraform validate` criterion is verified — clean in
both `terraform/live/platform-connectivity` and `terraform/live/workloads-prod`
(terraform 1.9.8, azurerm 5.0.1), alongside 87/0, 271/0, 85/0, 12/0 and
Factory CI 17/17. The "plan shows the flow-log resources against the chosen
NSGs only" criterion is **estate-gated** — the flag is off, so no plan can
show them until a PR flips it against a subscription whose spokes exist — and
folds into item 3.1, the same way item 2.1's residual did. Item number
retained so cross-references stay stable; record in
[CHANGELOG.md](CHANGELOG.md). Follow-ups opened as items 2.8–2.10 and folded
into item 5.2.

### 2.8 Make `nsg-flow-logs` storage replication a variable — CLOSED

Closed 2026-08-10 on the operator election the gate named ("an operator
election to make residency configurable ahead of one"), rather than waiting for
a residency-constrained engagement.

`account_replication_type` was hardcoded to `RAGZRS`, so every flow log was
asynchronously replicated to the Azure paired region **and readable there**,
with no opt-out short of forking the module. It is now
`storage_account_replication_type` on the module, validated against the six
real values, with `flow_log_storage_replication_type` passed through by every
layer that calls it — `platform-connectivity` and both workload layers, in both
trees, six call sites in each tree.

**The default is unchanged**, so no existing plan moves a byte. A
residency-constrained estate sets `LRS` or `ZRS` and gets no paired-region copy.
The rendered tfvars carries the knob commented out, next to the sentence
explaining why it matters — because a client under an EU/UK boundary needs to
see it without reading the module.

Note recorded with the variable: the zone-redundant options (`ZRS`, `GZRS`,
`RAGZRS`) need a region with availability zones, so `LRS` is the safe floor.

**Validation**: all three fixtures strict-pass 8/0 (which includes
`terraform validate` in the rendered tree); schema drift `InSync: True` with
the new variable mapped `literal:operator-supplied` in all three layers,
matching how `management_ip_ranges` is handled (contract #4); module READMEs
updated so the module-docs contract passes.

### 2.9 Make the flow-log storage account name overridable, then cover hub `fw_mgmt` — CLOSED

Closed 2026-08-09: the gate lifted when the operator gave the nod in-session
2026-08-09 (decision 0009 follow-up (b); no new decision record — the naming
change is an implementation of a ratified follow-up, not a new choice).
Shipped, both trees at parity: `nsg-flow-logs` gained a
`storage_account_name` variable defaulting to `null`, with the resource name
falling back through `coalesce()` to the unchanged composed
`stflowlogs${region_code}${environment}` so every existing caller renders the
name it already has, and a `validation` block enforcing Azure's 3–24
lowercase-alphanumeric rule on any supplied value; `hub-network` gained an
`nsg_ids` output in the same map shape as `spoke-network`'s, keyed `fw_mgmt`
and **empty** (not null, never an index into a zero-length resource) when the
hub deploys no NVA; and `platform-connectivity` gained one `nsg-flow-logs`
instance per hub region, named `stflowlogshub<region_code>prod` so it coexists
with `workloads-prod`'s `stflowlogs<region_code>prod` in the same region and
environment, `count`-gated on a new `enable_nsg_flow_logs` **defaulting to
`false`** *and* on `length(module.hub_*.nsg_ids) > 0` so an NVA-less hub does
not create a storage account with nothing to log. `enable_private_endpoint`
stays `false` (item 2.10 owns it) and `enable_traffic_alerts` `false` (no
action group reaches this layer). `variable-map.json` maps the connectivity
gate `literal:false`, matching the workload layers and the layer's own
`wire_management_workspace`. Contract **8a** is rewritten from "one instance per `(region,
environment)`" to "names must be distinct, and a second instance in a region
and environment must supply `storage_account_name`".
**Both validation criteria verified.** `terraform validate` clean in
`terraform/live/platform-connectivity` and `terraform/live/workloads-prod`
(terraform 1.9.8, azurerm 5.0.1), and `hub-network` exposes the `fw_mgmt`
output the connectivity instances consume. The "two instances in one region
and environment plan distinct storage accounts" criterion is proved from
configuration rather than from a plan — a real plan needs credentials this
environment does not have — by `factory/tests/Test-Renderer.ps1` §15e, which
pins the module's fallback expression, the workload callers' *absence* of an
override, the connectivity callers' overrides in both trees and in the render,
and the distinctness and legality of the four resulting names. Alongside:
87/0, 311/0 (was 271/0 — §15e adds 40 assertions), 85/0, 12/0, Factory CI
17/17. Record in [CHANGELOG.md](CHANGELOG.md).
**What remains**: both gates are still off, so the estate collects nothing
until a PR flips them — that flip is estate-gated and carried in item 3.1,
like items 2.1 and 2.3 before it.

### 2.10 Add `privatelink.blob.core.windows.net` and re-enable the flow-log private endpoint — CLOSED

Closed 2026-08-10 (decision 0009 follow-up (c); no new decision record — the
zone is the implementation of a ratified follow-up, and the two-layer split it
introduces is a contract fact, so it went into new **contract 9**). The gate
was technical, not an operator decision, and is now satisfied.

Shipped, both trees at parity. `platform-connectivity` owns the zone: a new
`deploy_blob_private_dns_zone` variable `count`-gates
`privatelink.blob.core.windows.net` in the primary hub's resource group and
links **both** hub VNets to it, and `blob_private_dns_zone_id` is exported
**unconditionally** — an empty string while the gate is off — so the workload
layers' existing remote-state read always finds the key. The workload layers
link their **own** spoke VNets to that zone through the `azurerm.hub` provider
alias they already hold for hub-side peering (the zone is in the connectivity
subscription; the default provider would not find it), and derive
`enable_private_endpoint`, `private_endpoint_subnet_id` and
`private_dns_zone_ids` from that single exported value. One flag in one layer
turns the whole path on and it cannot be half-set. `spoke-network` already
exposed `pe_subnet_id`, so no new subnet was needed on the workload side; the
non-production corpus layer puts the endpoint in the same first-rendered spoke
that already hosts the shared instance's resource group.

`nsg-flow-logs` gained two `lifecycle.precondition`s, because
`enable_private_endpoint` defaults to **true** while
`private_endpoint_subnet_id` and `private_dns_zone_ids` default to empty: a
caller that enables the endpoint without a subnet failed only at apply, and one
without a zone created an endpoint whose name never resolved. Both now fail at
plan.

**Renderer**: `deploy_blob_private_dns_zone` maps to the client's
`connectivity.privateDns.enabled` answer — the same key as `deploy_dns`, and
deliberately **not** `literal:false`. Neither reason for the flow-log flag's
constant applies: a zone has no volume-driven meter and no dependency that can
make a generated repository's first plan fail. Turning it on still creates no
endpoint, because those are gated on `enable_nsg_flow_logs`, which contract 8b
keeps constant.

**Validation**: node 87/0. The PowerShell suites and `terraform validate` could
not run in this environment — no `pwsh` and no `terraform` binary — so
`Test-Renderer.ps1` §15f (new) and the `fmt`/`validate` legs are CI's; §15f
pins the module preconditions, the gated zone and both hub links, the
default-off variable in both trees, the unconditional export, and for each of
the three workload files the remote-state read, the hub-aliased and gated
spoke links, all three endpoint arguments on every call, and the absence of
any hardcoded `false`.

**What remains**: the estate creates nothing until the gate is on, and no
endpoint until the flow-log gate is on too. Two residuals opened as items 2.11
and 2.12.

### 2.11 Give `hub-network` a private-endpoint subnet — CLOSED

Closed 2026-08-10. The gate was "which block of the hub address space", and
the answer turned out to be that **there isn't one** — which is itself the
finding, not a dodge.

**Why no derived index works.** Every other hub subnet comes from a
`cidrsubnet()` index off the hub space, but the free space differs by firewall
type and the two sets are **disjoint**. For a `10.0.0.0/16` hub:

| Firewall | Consumes | Free /20s |
| --- | --- | --- |
| `azfw` | `AzureFirewallSubnet` = the whole first quarter | `10.0.64.0`–`10.0.191.255` |
| `palo` / `fortinet` | `snet-fw-mgmt` (index 0) plus quarters 1 and 2 for trust/untrust | `10.0.16.0`–`10.0.63.255` |

Quarter 3 is full in both (gateway, bastion, two DNS-resolver subnets). So a
fixed index collides with one firewall type, and an index that varies by
firewall type would make the address plan depend on a security choice.

**Shipped**: `hub-network` gains `private_endpoint_subnet_prefix`, **null by
default**, CIDR-validated, creating `snet-private-endpoints-*` only when the
operator supplies a range from their own plan. The connectivity layer passes
one per hub and exports the subnet ID; the rendered tfvars carries both as
commented placeholders next to the reason they are not derived.

The hub's own flow-log endpoints now turn on when **three** conditions hold,
expressed once in a local so the two regional calls cannot drift: the blob
zone exists (items 2.10/2.12), the client asked for private endpoints (item
2.14), and a subnet prefix was supplied (this item). Any absent leaves
`enable_private_endpoint = false`, which is what has shipped since decision
0009.

**Not done, and available if you want it**: re-cutting the hub plan so a
universal index exists — `AzureFirewallSubnet` takes a `/18` where Azure asks
for a `/26` — would free quarter 0 for every firewall type. That changes an
existing subnet's prefix, so it is a deliberate topology change rather than
something to smuggle into this item.

**Validation**: `Test-Renderer.ps1` **455/0** (§15i new). The full
`Invoke-FactoryCI.ps1` runs locally now — every check green except
PSScriptAnalyzer, which cannot install here (PS Gallery blocked).
`terraform fmt -check` clean on both trees; `terraform validate` still needs
CI (`registry.terraform.io` is 403 through this proxy). §15i was
negative-tested, and the first version of its "prefix is not derived" check
was **vacuous** — a `[^}]*` class stopped at the `${var.region_code}`
interpolation in the subnet name and never reached `address_prefixes`. It now
extracts the block to a closing brace at column 0 and fails when the prefix is
replaced by a `cidrsubnet()` call.

### 2.12 Render the wizard's `connectivity.privateDns.zones` list — CLOSED

Closed 2026-08-10. No operator decision was needed for the list itself; the
two questions the item flagged were answered as stated below and are cheap to
overturn.

Shipped, both trees at parity. `platform-connectivity` takes a
`private_dns_zones` list, renders it from `connectivity.privateDns.zones`, and
creates the zones with `for_each`, linking **every** zone to both hub VNets;
the link name carries a slug of the zone because link names allow a narrower
character set than zone names. `deploy_blob_private_dns_zone` was renamed
`deploy_private_dns_zones` now that it gates a list, and `moved` blocks carry
the `count` → `for_each` address change so a client who applied item 2.10 sees
a move rather than a destroy/create. `blob_private_dns_zone_id` is now looked
up **by name**: a client list that omits the blob zone yields an empty string
and their flow-log endpoints stay off, instead of an index error at plan or an
endpoint bound to the wrong zone. `private_dns_zone_ids` exports the whole map
for future callers.

**Answered — blank list.** An empty list means
`privatelink.blob.core.windows.net` alone, which is what item 2.10 shipped.
The schema description and the wizard hint both promised "the CAF default zone
set for the services you enabled" and nothing implemented it; the wording was
corrected in both places. Creating a set of zones a client never asked for —
their box is pre-checked — is a worse way to make that promise true than
saying what actually happens. Reversing this means adding a default set in one
place, `local.private_dns_zones`.

**Answered — `centralizedInHub`.** Contract 9 puts zone ownership in the
connectivity layer, so `false` has no implementation. It is now **refused**
rather than silently ignored: new render guard **G23** blocks it, and
`site/app.js` rejects it in the wizard so the client sees it before export. An
absent key reads as `true`, so older configurations still render. Building the
decentralized path would contradict contract 9 and needs an ADR first.

**Bounds (contract #7).** Zone names are validated in all three places, and
the wizard regex, the schema `items.pattern` and the Terraform validation are
the *same expression*, so none is looser than the one to its right. The schema
also gained `uniqueItems` and `maxLength: 253`; Terraform rejects duplicates
for the same reason — two entries of one name are one zone and would collide
on the link name.

**Validation**: node 87/0. As with item 2.10, this environment has no `pwsh`
and no `terraform`, so `Test-Renderer.ps1` §15f (updated for the rename) and
§15g (new), the PowerShell suites and the `fmt`/`validate` legs are CI's.
§15g pins the three-way bound equality as an *ordering* rather than three
separate regexes, G23's existence, severity, documentation and its
default-true reading, a decentralized config failing the render with nothing
written, and the absence of the CAF promise from both places that made it.

**What remains**: the zones are still created only when
`deploy_private_dns_zones` is on, and still produce no endpoint until
`enable_nsg_flow_logs` is on too. `connectivity.privateEndpoints.enabled` and
`denyPublicNetworkAccessPolicy` remain collected and unrendered — a separate
gap from this item, not opened here.

### 2.13 Guard ID `G22` covers two unrelated conditions — CLOSED

Closed 2026-08-10. The gate — "is a guard ID a stable client-facing identifier
or an internal label?" — was answered by reading the code rather than by an
operator call: an ID reaches a client **only** as transient console text
(`Write-LzRenderFail "$($g.Id): $($g.Message)"`). Nothing persists or keys off
one: not the schema, not a workflow, not any generated artifact. It is a
diagnostic label, so renumbering is safe.

Shipped. The missing-subscription case is now **G24** with its own README row;
`G22` keeps its documented meaning, the missing non-production spoke CIDR.
`G22` still appears at two call sites and that is **correct** — the primary and
DR variants of one condition a client fixes in one place.

**Corrected criterion.** This item said the fix would be proved by emptying
§15g's allowance list. That was written on the wrong assumption that all three
`G22` sites were the bug. The list is not empty and should not be; it is
renamed `$multiUseGuardIds` and now means "declared, deliberate multi-use"
rather than "known defect". A new undeclared repeat still fails.

**Found while fixing it**: `G15` (custom naming standard with an empty
pattern) had no README row and never had one. Both gaps came from nothing
checking, so the durable fix is two new §15g invariants — every ID the chain
raises has a table row, and every documented ID still exists in the chain.
The coverage check is scoped to **table rows**, not the whole README: scanning
the file made it vacuous, because the paragraph explaining the G15 gap names
G15, so deleting its row still counted as documenting it. Both invariants were
negative-tested — removing the G15 row fails, and reintroducing a duplicate ID
fails three assertions.

**Validation**: `Test-Renderer.ps1` **412/0** run locally (was 410/0), plus
Bootstrap 85/0, CI 12/0, Discovery 60/0, Scaffold 16/0, Validate 18/0, Import
10/0, Dogfood 10/0, Release 10/0, node 87/0. PowerShell is installed in this
environment now, so these are real runs rather than CI's. PSScriptAnalyzer and
the terraform legs remain CI's.

### 2.14 Render `connectivity.privateEndpoints` — CLOSED

Closed 2026-08-10. Both fields under `connectivity.privateEndpoints` had been
collected by the wizard since the factory shipped and read by nothing — the
same shape of gap as item 2.12, different fields.

**`enabled`** now renders to `enable_private_endpoints` in both workload layers
and **ANDs** with the connectivity layer's private DNS zone. Default `true`
matches the schema and the pre-checked box, so nothing changes for anyone who
left it alone; the client who *unticked* it now gets the effect they asked for,
which they previously did not. The spoke VNet links stay ungated — they cost
nothing and make the zone usable the moment the answer changes. Contract 9 is
extended with the two-yes rule.

**`denyPublicNetworkAccessPolicy`** now assigns a custom initiative — storage
accounts and key vaults — over the **Landing Zones** management group, gated on
`assign_public_network_access_policy` (default off).

Two judgment calls, both flagged and cheap to reverse:

- **The effect is `Audit`, not `Deny`.** This estate creates storage accounts
  that deliberately keep public network access enabled behind network rules:
  the flow-log accounts, and the state account during setup. A `Deny` at
  landing-zone scope would fail a generated repository's first apply on the
  platform's own resources — the failure mode decision 0009 exists to prevent.
  The wizard label and the schema description were reworded from "denying" to
  match. **To reverse**: set `public_network_access_effect` to `Deny`, once the
  estate's own accounts are behind private endpoints.
- **Scope is Landing Zones, never root or platform.** The platform group holds
  the Terraform state account, which cannot be private-endpoint-only during
  bootstrap — the client's own machine creates the estate from it
  ([decision 0004](docs/decisions/0004-factory-copy-is-a-disposable-installer.md)).
  §15h asserts the scope positively *and* negatively.

**Custom definitions rather than built-in GUIDs**, matching the module's
existing `policy-tls-minimum.tf`: a custom definition carries its own
parameterised effect instead of depending on a built-in whose allowed effects
can change. The trade is coverage — storage and key vaults, not the ~20
services the ALZ `Deny-Public-Endpoints` initiative reaches. Adding a service
is one definition plus one reference in the set.

**Validation**: `Test-Renderer.ps1` **429/0** (+17, §15h new), every other
PowerShell suite green, node 87/0, and `terraform fmt -check` clean on both
trees — all run locally. `terraform validate` could NOT run:
`registry.terraform.io` is 403 through this environment's proxy, so the
provider schema is unavailable. That leg and PSScriptAnalyzer remain CI's.
§15h was negative-tested — widening the scope to root fails two assertions and
dropping the AND fails another.

**What remains**: the initiative covers two PaaS services, and `Audit` reports
rather than blocks. Neither is a gap this item left open — both are the stated
starting posture.

### 2.15 V07 and V08 fail against real tflint and checkov — CLOSED

Found and closed 2026-08-10. Item 3.1 had carried a criterion from item 1.1 —
"the strict run must confirm V07/V08 pass with real tflint/tfsec and **no skips
recorded**" — unproven only because the tools were believed unavailable. They
install (tflint 0.64.0 from its GitHub release, checkov 3.3.9 from PyPI), the
run happened, and **V07 and V08 both failed**. They now pass.

**Two blind spots caused it, both about what the 2026-08-06 run happened to
use.** It rendered `azurerm-config.json` and it used tfsec. Rendering
`sample-config.json` (hcp-terraform) surfaced six fresh
`terraform_unused_declarations`, and checkov — which V08 tries **first** —
reported 40 failures where tfsec reported one.

**The scanner is now pinned to checkov.** A gate whose verdict depends on which
of three tools the runner happens to have installed is not a gate. tfsec is
also archived upstream.

**All three fixtures now pass all eight gates with zero gate skips** —
`sample` (hcp-terraform), `azurerm`, and `nonprod`. The third was checked
precisely because the finding was that only one render shape had ever been
linted, and it duly failed on something the other two did not: the per-
environment spoke CIDR variables, unreferenced when a client selects only some
non-production environments.

**Resolution, conservative reading (operator-directed).** Genuinely-real
findings fixed; findings that contradict decisions already taken suppressed at
the resource with a stated reason. **Nothing was suppressed silently** — every
directive names what it defers to.

*Fixed* (3 rules): managed identity on the recovery-services vault
(`CKV2_AZURE_35`) and the automation account (`CKV2_AZURE_36`); a SAS
expiration policy on the flow-log storage (`CKV2_AZURE_41`).

*Suppressed with reasons* (9 rules, 15 directives): `CKV_AZURE_59` and
`CKV2_AZURE_40` on flow-log storage — public access is deliberate and
network-rule fronted (decision 0009), and whether Network Watcher can write to
a shared-key-disabled account is **unverified**, so it was not flipped on a
guess; `CKV2_AZURE_1` — CMK needs `keyvault-cmk`, a decided deferral (item
2.4); `CKV_AZURE_33` — no queue service exists to log; `CKV_AZURE_43` — the
name is an interpolation checkov cannot resolve; `CKV_AZURE_216` — threat
intelligence is set on the attached firewall **policy**, which governs;
`CKV2_AZURE_24` — closing the automation account's public access without a
private endpoint would trade a finding for a broken control plane;
`CKV2_AZURE_31` ×7 — see the correction below: **every** flagged subnet can
carry an NSG and does not yet. Only the `gateway` directive rests on "Azure
forbids it", and it suppresses nothing, because that subnet is not flagged.

**Corrected 2026-08-10, after this item was first written**: the summary above
originally said part of the `CKV2_AZURE_31` suppression was justified because
`GatewaySubnet` and `AzureFirewallSubnet` cannot carry an NSG. Neither is
flagged by checkov at all. All 12 findings are on `bastion`, `dns_inbound`,
`dns_outbound`, `fw_trust`, `fw_untrust` and `private_endpoints` — **six
subnets per hub, every one of which can take an NSG**. The "impossible to fix"
framing applied to none of them and understated the outstanding work; it is
now item 2.16.

**Two things this deliberately did NOT do**, both recorded rather than hidden:
the six hub subnets that could take an NSG still do not (authoring correct
per-subnet rules is real work, and a wrong Bastion NSG breaks Bastion), and
shared-key authorization on flow-log storage stays enabled pending
verification. Both are named in their suppression text, so the next reader
finds them at the resource rather than in a changelog.

**Validation**: all three fixtures, `LZ_VALIDATE_STRICT=true`, `8 passed, 0
skipped`, checkov exiting clean. Full `Invoke-FactoryCI.ps1` green except
PSScriptAnalyzer (PS Gallery blocked here).

### 2.16 Six hub subnets carry no NSG — BASTION DONE, FIVE REMAIN

`CKV2_AZURE_31` fires on **six subnets per hub**, both regions — twelve
findings — and every one of them can take a network security group. They are
suppressed with a stated reason (item 2.15) so the gate is honest about the
difference between *impossible* and *not done*, but suppression is not the fix.

| Subnet | What an NSG has to allow |
| --- | --- |
| ~~`bastion` (`AzureBastionSubnet`)~~ | **Done 2026-08-10.** `azurerm_network_security_group.bastion` carries Microsoft's prescribed set — 443 inbound from Internet, GatewayManager and AzureLoadBalancer, 8080/5701 within the VNet; 22/3389 outbound to VirtualNetwork, 443 to AzureCloud, 8080/5701 within the VNet, 80 to Internet — plus the documented explicit denies. |
| `dns_inbound` / `dns_outbound` | Delegated to `Microsoft.Network/dnsResolvers`. Azure permits an NSG; it must not block resolver traffic on 53/UDP+TCP. |
| `fw_trust` / `fw_untrust` | NVA data-path subnets (palo/fortinet only). Rules follow the appliance vendor's guidance, so this half is firewall-type dependent. |
| `private_endpoints` | Arrived with item 2.11. Private endpoints ignore NSGs unless the subnet sets `private_endpoint_network_policies = "Enabled"` — which this module already does, so an NSG here would actually apply. |

Not one rule set: three or four different ones, two of them
vendor-conditional. That is why it is an item rather than a line in 2.15.

**Bastion, done 2026-08-10.** Two things stated rather than buried:

- **The rules are verified against Microsoft's documented set
  ([bastion-nsg](https://learn.microsoft.com/azure/bastion/bastion-nsg)).**
  They were first written without being able to re-read that page —
  `learn.microsoft.com` is unreachable from the authoring environment — and
  were then checked line by line against the same article's source in
  `MicrosoftDocs/azure-docs` on GitHub, which *is* reachable (PR #92): every
  source, destination, port and protocol matches, and one rule was renamed to
  the documented `AllowHttpOutbound`. That page remains the authority if the
  two ever disagree.
- **The failure mode is loud, not silent.** Azure validates this NSG when a
  Bastion *host* is deployed and fails the deployment if a required rule is
  missing. This repository deploys only the placeholder subnet, so no host
  exists to break today, and the first real deployment would surface an error
  rather than a half-working host.

The `CKV2_AZURE_31` suppression on `bastion` stays, with its reason **rewritten
to the truth**: the NSG exists and is associated; checkov does not resolve the
association because it is count-indexed — the same graph limitation that hides
the SAS policy on flow-log storage.

The Bastion NSG is deliberately **not** added to the `nsg_ids` output. That
output feeds the connectivity layer's flow-log calls, and widening it would
change flow-log scope, which decision 0009 set deliberately. That is a
decision-0009 change, not an NSG change.

**Owner**: `azure-platform-architect` (design) → `terraform-module-engineer`.
**The remaining five are gated on design input, and that was checked rather
than assumed (2026-08-10).** Bastion was doable unattended because Microsoft
prescribes an exact rule table. The others have no equivalent:

- **`dns_inbound` / `dns_outbound`** — Microsoft publishes **no NSG rule set**
  for DNS Private Resolver subnets. Three articles were read from
  `MicrosoftDocs/azure-docs`
  (`dns-private-resolver-overview.md`,
  `dns-private-resolver-get-started-portal.md`,
  `private-resolver-endpoints-rulesets.md`) and none mentions network security
  groups at all; the documented subnet restrictions cover size, delegation and
  IPv6, not filtering. Correct rules depend on **which client subnets and
  on-premises ranges will query the resolver** — an input this repository does
  not hold.
- **`fw_trust` / `fw_untrust`** — the authority is the NVA vendor (Palo Alto or
  Fortinet), not Microsoft, and the rules differ per appliance. Also
  firewall-type conditional, so they only exist on a `palo`/`fortinet` hub.
- **`private_endpoints`** — an NSG here would genuinely apply (the module sets
  `private_endpoint_network_policies = "Enabled"`), but the rules depend on
  which spokes must reach which endpoint. Today the only endpoint is the
  flow-log storage one.

So this is not "not done yet" — it is **waiting on the client's DNS design and
firewall choice**. Writing rules without them would be guessing at a security
control, which is how a subnet ends up with an NSG that looks protective and
either blocks nothing or blocks the wrong thing.
**Validation**: as each subnet gains an NSG, its `CKV2_AZURE_31` suppression is
either removed or rewritten to the count-indexed-association reason; all three
fixtures strict-pass; a Bastion host actually connects — which this environment
cannot prove, so that waits on a real estate.

### 2.17 Shared-key authorization stays enabled on flow-log storage — CLOSED

Answered 2026-08-10, the same day it was opened, and the answer is **do not
disable it**.

Microsoft's NSG flow-log documentation settles it under *Storage account*
requirements: **"Self-managed key rotation: If you change or rotate the access
keys to your storage account, NSG flow logs stop working. To fix this problem,
you must disable and then re-enable NSG flow logs."** Flow logs authenticate to
the account with its **access keys**, so `shared_access_key_enabled = false`
does not merely risk breaking delivery — it breaks it.

That also explains why the state account can disable shared keys and this one
cannot: nothing writes to the state account except Terraform, over AAD.

**How it was answered without Azure access.** `learn.microsoft.com` is
unreachable from this environment, but the same articles are open source in
`MicrosoftDocs/azure-docs` on GitHub, which is reachable. The citation above is
from `articles/network-watcher/nsg-flow-logs-overview.md`. That route is worth
remembering: it answers most "what does Azure require here" questions this
repository hits, without an Azure subscription.

The `CKV2_AZURE_40` suppression stays and now carries the citation instead of
an admission of ignorance. **No code changed** — the conservative call made
under uncertainty turned out to be the correct one.

### 2.4 Implement `keyvault-cmk` and `sentinel-siem`

Both are `check "module_not_implemented"` scaffolds, render-blocked (guards
G02/G03) — a **decided deferral**, not drift.
**Owner**: `azure-platform-architect` (design) → `terraform-module-engineer`.
**Gate**: operator re-opens the deferral — [REVIEW.md](REVIEW.md) §14 lists
the design inputs required (key hierarchy, vault scope, connectors,
retention split).
**Validation**: modules render, `terraform validate` passes, wizard labels
updated from scaffold-only.

### 2.5 Wire `Configure-DeploymentOptions.ps1` output into Terraform

`.azure/deployment-options.yaml` is a planning-only artifact; no layer reads
it. Two of the three modules it would gate are the item-2.4 scaffolds.
**Owner**: `alz-orchestrator` (cross-domain: script, renderer, layers).
**Gate**: item 2.4 ships first — [REVIEW.md](REVIEW.md) §16.
**Validation**: enabling an option in the YAML changes the corresponding plan.

### 2.6 Record the generated-repo ownership policy

Mechanism is settled (`github.ownershipModel`/`ownerName` are required schema
fields); what is open is engagement policy — which owner value CBTS uses and
whether repos are transferred to the client afterward. Watch schema risk GH1
(`personal` on a Free plan silently loses protected environments).
**Owner**: operator decides; `docs-knowledge-curator` records.
**Gate**: [REVIEW.md](REVIEW.md) §13.
**Validation**: policy recorded in a decision record; wizard/docs reference it.

### 2.7 Update dot-folder contract text to the 2026-08-07 file contract — CLOSED

Closed 2026-08-07 (PR #77): the gate lifted when the operator approved the
dot-folder edits in-session. `docs-knowledge-curator.md`'s "What lives where"
now states the four-file root contract and the `docs/USER-CHECKLIST.md`
location; the `020-rbac-validation.yml` comment cites REVIEW.md §1. The
validation grep for "PROD-TODO" returns no live-instruction references.
Item number retained so cross-references stay stable; record in
[CHANGELOG.md](CHANGELOG.md).

---

## Phase 3 — Authenticated-toolchain execution

Needs a provisioned toolchain with real `az`/`gh` sessions (or the named
external access); no Azure estate mutation implied.

### 3.1 Execute the Stage 9/10/11 suites and the engagement-wrapped validation gate

The **standalone** validation gate is done (executed 2026-08-06 — record in
[REVIEW.md](REVIEW.md) §7). What remains: the broker/import/scaffold-apply
suites against authenticated `az`/`gh`, and the validate phase inside the full
engagement wrapper (discovery → broker → render → validate → scaffold,
`scripts/Invoke-CustomerEngagement.ps1`) with real discovery artifacts.
Carried forward from item 1.1 (closed 2026-08-07 with this criterion unmet),
the strict V07/V08 skip-free pass — **discharged by item 2.15 (closed
2026-08-10)**: tflint 0.64.0 and checkov 3.3.9 installed and ran, the scanner
is pinned to checkov, and all three fixtures (sample, azurerm, nonprod) pass
all eight gates `8 passed, 0 skipped` under `LZ_VALIDATE_STRICT=true`. No
authenticated run is needed for that criterion any more.
Carried forward from item 2.1 (closed 2026-08-07): confirm against a real
estate that a broker apply registers the decision-0006 namespaces (audit
entries `registered`/`already-registered`, none left `pending`) and that the
first apply into a fresh subscription no longer fails
`MissingSubscriptionRegistration` — the code path is test-covered, but the
end-to-end proof needs authenticated `az` and a fresh subscription.
Carried forward from items 2.3 and 2.9 (closed 2026-08-09), the estate-gated
flag flips both items fold into this one: `enable_nsg_flow_logs` defaults to
`false` in both the workload and connectivity layers, so the estate collects
nothing — and no plan can show the flow-log resources — until a PR flips the
flags against a real estate whose spoke (and, for the hub instances, NVA)
NSGs exist.
**Owner**: `alz-orchestrator` (multi-stage execution).
**Gate**: provisioned, authenticated toolchain — [REVIEW.md](REVIEW.md) §7.
**Validation**: suite runs recorded with plan/audit evidence files; wrapper
completes plan-first end to end; the flag-flip PR's plan shows the flow-log
resources against the chosen NSGs only (item 2.3's carried criterion).

### 3.2 Publish the prepared wiki review edits

The 2026-08-06 content review of the 11 migrated wiki docs is complete;
verdicts and the ready-to-apply patch live in
[docs/wiki-review/](docs/wiki-review/README.md). Only the push is blocked.
**Owner**: `docs-knowledge-curator`.
**Gate**: wiki write access — [REVIEW.md](REVIEW.md) §15 (commands in the
review README).
**Validation**: the 11 wiki pages carry the HISTORICAL banner; `Home.md`
labels corrected.

---

## Phase 4 — Go-live chain

**Deferred, not pending** — the operator has not opened the go-live phase
([REVIEW.md](REVIEW.md) §§1–9 banner). Chronological order within the chain:

### 4.1 Confirm the engagement tenant and create the live identity estate

No landing-zone identity estate exists; every PR fails `azure/login`. The
reachable tenant is a regulated-industry client's — creating identities there
without engagement-owner confirmation is prohibited.
**Owner**: operator confirms tenant; `github-actions-engineer` supports the
bootstrap run. **Gate**: [REVIEW.md](REVIEW.md) §1.
**Validation**: `azure-auth-test.yml` token exchange green from a real PR.

### 4.2 Enable required status checks on upstream `main` (+ settings read-back)

`main` has no `required_status_checks` (six dependabot PRs merged red
2026-08-02). Upstream factory repo only — client copies are never hardened
(decision 0004). Includes the settings not checkable from a clone (secret
scanning, required approvals).
**Owner**: `github-actions-engineer`. **Gate**: repository administration —
[REVIEW.md](REVIEW.md) §2 (single-owner approval caveat noted there).
**Validation**: GitHub API read-back shows the required contexts enforced.

### 4.3 Set GitHub Pages source to "GitHub Actions"

One-time repo setting; `deploy-pages.yml` is ready.
**Owner**: operator (Settings → Pages). **Gate**: [REVIEW.md](REVIEW.md) §8.
**Validation**: published site serves `site/` at root, `frontend/` under
`/frontend/`.

### 4.4 Supply `-SandboxSubscriptionId` at bootstrap (per engagement)

Without it, platform-management's sandbox-cleanup Contributor assignment fails
`AuthorizationFailed`. Only blocks sandbox-enabled engagements.
**Owner**: operator input per engagement. **Gate**: [REVIEW.md](REVIEW.md) §6.
**Validation**: broker plan shows the sandbox RBAC assignment scoped to the
real subscription.

### 4.5 Verify the pipeline runs green end to end

No recorded successful run of `010-terraform-init.yml`,
`020-rbac-validation.yml`, `terraform-plan.yml`, `terraform-apply.yml`.
**Owner**: `deployment-troubleshooter` if anything stays red after 4.1.
**Gate**: item 4.1 — [REVIEW.md](REVIEW.md) §3.
**Validation**: successful runs of all four workflows on a real PR/push.

### 4.6 Resolve the backend duality / TFC migration (Issue #11)

HCP Terraform is the recorded default; `terraform/live/*` is azurerm; the
bootloader and workflow 010 assume TFC.
**Owner**: `github-actions-engineer`. **Gate**: interactive TFC
org/workspace/token setup — [REVIEW.md](REVIEW.md) §9,
[Issue #11](https://github.com/HybridCloudWorks/Template-LZDeployment/issues/11).
**Validation**: one backend per stack, init green against it.

### 4.7 Execute and accept the Stage 13 dogfood instance

`factory-version.json` carries `dogfoodInstanceAppliesGreen = false`.
Gate-by-gate runbook:
[docs/runbooks/stage13-dogfood-execution.md](docs/runbooks/stage13-dogfood-execution.md);
acceptance criteria: [docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md) Stage 13.
**Owner**: operator executes; `alz-orchestrator` sequences support.
**Gate**: items 4.1–4.5 — [REVIEW.md](REVIEW.md) §4.
**Validation**: every rendered layer applies green; read-back evidence
accepted; `dogfoodInstanceAppliesGreen=true` set in a separately reviewed PR.

---

## Phase 5 — Release-time items

### 5.1 Run Stage 14 release attestation and the release-gate PR

Until v1.0.0 gates pass, every customer deployment is formally a verification
exercise (factory v0.9.0, `oidcTokenExchangeVerifiedLive = false`).
**Owner**: operator; `github-actions-engineer` supports.
**Gate**: item 4.7 — [REVIEW.md](REVIEW.md) §5.
**Validation**: `release-readiness-report.json` with `readyForPromotion=true`;
separate reviewed release-gate PR.

### 5.2 Review module-README cost estimates against current Azure pricing

The variable tables are machine-enforced (`factory/ci/Test-ModuleDocs.ps1`);
the cost figures are not derivable from HCL and go stale against Azure list
prices.
Carried forward from item 2.3 (closed 2026-08-09) — decision 0009 follow-up
(d): `terraform/modules/nsg-flow-logs/README.md`'s Cost section now states a
per-GB formula whose rates (`C` ≈ $0.50/GB collection, `P` ≈ $2.00/GB Traffic
Analytics at 60 min, `I` ≈ $2.76/GB Log Analytics ingestion, `S` ≈
$0.05/GB-month RA-GZRS) are **labelled unverified in the file**: the authoring
environment had no egress to `prices.azure.com` (403 at the proxy) and the
Azure MCP `pricing` tool was refused. Refresh them from an environment with
egress and re-date the section. Decision 0009's Q2 resolution stands until
then — **no figure in that README or in the decision record may be quoted to a
client as a price**.
**Owner**: `azure-cost-governance` prepares; a human accepts the figures.
**Gate**: release cadence — [REVIEW.md](REVIEW.md) §17 (cannot be automated);
for the 0009 rates specifically, an environment with egress to
`prices.azure.com`.
**Validation**: reviewed figures dated in each module README; the
`nsg-flow-logs` rate block loses its "UNVERIFIED" label only when a human has
accepted verified figures.

### 5.3 Bump `factory-version.json` in lock-step

Bumping the version forces the wizard `FACTORY_VERSION` constant, four test
fixtures, and the Stage 14 v0.9.0 evidence-selection instructions
([docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)) to move together — an
operator-record change (CHANGELOG, 2026-08-06).
**Owner**: `github-actions-engineer`.
**Gate**: item 5.1 promotion decision.
**Validation**: `node factory/tests/test.js` and
`pwsh -File factory/tests/Test-Renderer.ps1` green after the bump.

---

## Key documents

- **[REVIEW.md](REVIEW.md)** — blocker registry: who can unblock each gated
  item above, and the next concrete action
- **[CHANGELOG.md](CHANGELOG.md)** — record of shipped work
- **[docs/USER-CHECKLIST.md](docs/USER-CHECKLIST.md)** — per-stage operator
  activities (moved from the root 2026-08-07; the renderer separately emits a
  per-customer copy into generated repos)
- **[docs/decisions/](docs/decisions/)** — decision records;
  **[docs/runbooks/](docs/runbooks/)** — operator procedures;
  **[docs/wiki-review/](docs/wiki-review/README.md)** — wiki review evidence
- **[GitHub wiki](https://github.com/HybridCloudWorks/Template-LZDeployment/wiki)** — operator guidebook and historical source material

---

**Owner**: Platform Engineering
