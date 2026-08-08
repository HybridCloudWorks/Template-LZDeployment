# Decision 0009 — NSG flow-log scope, workspace target, and hosting stack

- **Status**: **Proposed** — awaiting operator ratification. **Nothing is
  implemented**; no `.tf` file was touched by the authoring pass and the
  [REVIEW.md](../../REVIEW.md) §11 gate remains closed.
- **Date**: 2026-08-08
- **Deciders**: operator (ratification pending); `azure-platform-architect`
  (options), `azure-cost-governance` (costing) — authored under
  `alz-orchestrator`
- **Technical depth**: L300 (implementation)

## Context and Problem Statement

`terraform/modules/nsg-flow-logs/` has existed since Phase 2 with secure
defaults and **zero `terraform/live/*` callers**. The module is rendered into
every generated repository (it appears in `render-manifest.json`) but no
rendered layer calls it either. The consequence is the same on both sides:
**not one NSG flow log is collected anywhere**, in this repository's own
deployment or in any repository the factory produces.

That is not a dormant feature. The wizard **already asks for it**:
`factory/schema/lz-config.schema.json:586` defines
`security.nsgFlowLogs.{enabled,retentionDays,trafficAnalytics}` with
`enabled` and `trafficAnalytics` defaulting to `true`, and
`site/index.html:701-702` renders both as pre-checked boxes with a retention
field. No entry in `factory/renderer/variable-map.json` consumes any of the
three keys. **A client ticks "NSG flow logs", the answer is written into
`lz-config.json`, and nothing reads it.** The gate is therefore not "should
we add telemetry" — it is "the product already promises this, on what terms
do we honour it".

The reason this was never wired blind (REVIEW.md §11) is that the two open
choices set **cost and data-residency posture**, not just wiring: which NSGs
populate `var.nsg_ids` (the module does not auto-discover — see its README's
"Scope: Explicit NSG List" section), and which Log Analytics workspace
receives Traffic Analytics.

### What the module already gives, for free

Live and corpus copies are at **byte parity** (`diff -rq` clean, 2026-08-08).
One module instance produces:

| Resource | Note |
| --- | --- |
| `azurerm_storage_account.flow_logs` | Standard, `RAGZRS`, TLS1_2 floor, `default_action = "Deny"` with trusted-services bypass, versioning and delete-retention at `flow_log_retention_days` |
| `azurerm_private_endpoint.flow_logs_blob` | `count`-gated on `enable_private_endpoint` (default **true**) |
| `data.azurerm_network_watcher.main` | reads `NetworkWatcher_${location}` in `NetworkWatcherRG` |
| `azurerm_network_watcher_flow_log.nsg_flow_logs` | `for_each = var.nsg_ids`, v2 logs, retention policy, Traffic Analytics block |
| `azurerm_monitor_diagnostic_setting.flow_logs_storage` | blob-service `allLogs` + `AllMetrics` into the workspace |
| `azurerm_monitor_scheduled_query_rules_alert_v2.high_traffic_alert` | `count`-gated on `enable_traffic_analytics && enable_traffic_alerts` |
| `azurerm_monitor_scheduled_query_rules_alert_v2.denied_traffic_alert` | same gate; severity 1 |

Inputs of consequence: `nsg_ids` (map, default `{}`), the **three separate
workspace inputs** `log_analytics_workspace_id` (short),
`log_analytics_workspace_resource_id` (full ARM) and
`log_analytics_workspace_region` — all required — plus
`flow_log_retention_days` (90), `enable_traffic_analytics` (true),
`traffic_analytics_interval` (10 or 60, default 60), and
`enable_private_endpoint` (true) with `private_endpoint_subnet_id` /
`private_dns_zone_ids`.

### The NSGs that exist to wire

Verified 2026-08-08, both trees at parity.

| Stack | Module instances | NSGs each | Total |
| --- | --- | --- | --- |
| `terraform/live/platform-connectivity` | `hub_primary`, `hub_dr` | `fw_mgmt` — **`count`-gated on `local.has_nva`** (`hub-network/main.tf:142`) | 0, or 2 in an NVA estate |
| `terraform/live/workloads-prod` | `spoke_prod_primary`, `spoke_prod_dr` | `app` (`spoke-network/main.tf:45`), `data` (104), `pe` (158) | **6** |
| `terraform/live/sandbox` | `sandbox` | none | 0 |
| **Live total** | | | **6, or 8 with an NVA** |
| Corpus `platform-connectivity` | 2 hubs | `fw_mgmt` gated | 0 or 2 |
| Corpus `workloads-prod` | 2 spokes | 3 | 6 |
| Corpus `workloads-nonprod` | `spoke_{dev,test,uat}_{primary,dr}` | 3 | **18** |
| **Corpus total** | | | **24, or 26 with an NVA** |

**Neither `hub-network` nor `spoke-network` outputs an NSG ID.** Their
`outputs.tf` files export VNet, subnet, resource-group, route-table and
firewall values only. Any wiring must add NSG-ID outputs to those modules in
**both** trees — a corpus↔live parity change in
[contract #5](../CROSS-DOMAIN-CONTRACTS.md#5-spoke-network-provider-alias)
territory, since `spoke-network` is the module whose two copies contract #5
already pins at parity.

### Four constraints that bind every option below

These were discovered while costing the options and they narrow the field
more than the cost figures do.

1. **The storage account name is not unique per call.**
   `main.tf:6` sets `name = "stflowlogs${var.region_code}${var.environment}"`
   with no override. Storage account names are **globally unique**, so the
   estate can host **at most one module instance per `(region_code,
   environment)` pair** — across all stacks and all subscriptions. A
   connectivity call for the primary hub (`scus`/`prod`) and a workloads-prod
   call for the primary spoke (`scus`/`prod`) both want
   `stflowlogsscusprod` and the second one fails. Covering hub *and* spoke
   NSGs simultaneously requires a module change (an overridable name or a
   name suffix), not just a second call.

2. **Network Watcher is regional *and* per-subscription.** The module reads
   `NetworkWatcher_${var.location}` in `NetworkWatcherRG` through the
   **default provider**, and `azurerm_network_watcher_flow_log` is created
   against that Network Watcher. The module declares no
   `configuration_aliases`, so **one instance can only reach NSGs in its own
   subscription**. A central connectivity-hosted call therefore cannot cover
   workload-subscription NSGs at all — not "awkwardly", but not at all —
   without a module change mirroring `spoke-network`'s alias pattern. And a
   dual-region estate needs at least two instances regardless.

3. **The workspace triple cannot be satisfied from what is exported today.**
   The module needs the short workspace GUID, the full ARM resource ID, and
   the region. `management-baseline/outputs.tf:3` exports exactly one value,
   named `log_analytics_workspace_id` — and its value is
   `azurerm_log_analytics_workspace.alz.id`, the **full ARM ID**, not the
   short GUID the module's identically-named input wants. The name collision
   is a trap: passing the existing output straight into
   `log_analytics_workspace_id` type-checks and plans, and produces a broken
   Traffic Analytics configuration. Wiring requires **two new outputs** on
   `management-baseline` (the `workspace_id` attribute and `location`) and
   matching stack outputs, in both trees.

4. **The private endpoint default cannot currently be satisfied.**
   `enable_private_endpoint` defaults `true` and needs
   `private_dns_zone_ids`. **No `azurerm_private_dns_zone` resource exists
   anywhere in `terraform/modules/`, `terraform/live/`, or
   `factory/templates/terraform/`** except `backend-bootstrap/main.tf:133`,
   which is a different subscription and a different purpose. (The schema's
   `connectivity.privateDns.zones` is likewise unimplemented.) Wiring must
   either set `enable_private_endpoint = false` — a knowing, documented
   posture reduction — or add a `privatelink.blob.core.windows.net` zone and
   VNet link first.

---

## Choice A — which NSGs populate `var.nsg_ids`

The cost model (below) is the reason this choice is less expensive than it
looks: **flow-log cost scales with the traffic volume crossing the logged
NSGs, not with the NSG count.** Adding a low-traffic NSG to the map is close
to free; adding a high-traffic one is not.

One real nuance: `app` and `data` sit on subnets in the same spoke, so an
app→data flow **traverses both NSGs and is logged twice**. Including both is
the intent (you want each side's allow/deny verdict), but it does mean
intra-spoke east-west traffic is billed twice through the pipeline.

| | Scope | Live NSGs | Corpus NSGs | What it sees | What it misses |
| --- | --- | --- | --- | --- | --- |
| **A0** | Do nothing — keep zero callers | 0 | 0 | nothing | everything; and the wizard keeps asking a question with no consumer |
| **A1** | Spoke `app` + `data` only | 4 | 16 | workload east-west and north-south at the compute and data tiers | private-endpoint traffic — the data-exfiltration path most worth logging |
| **A2** | All three spoke NSGs (`app`, `data`, `pe`) | **6** | **24** | everything A1 sees, plus every flow to and from private endpoints | hub/NVA management-plane traffic |
| **A3** | Hub `fw_mgmt` only | 0–2 | 0–2 | management access to the NVA | all workload traffic; **and it does not exist in an Azure Firewall estate** (`has_nva` false) |
| **A4** | Everything (A2 + A3) | 6–8 | 24–26 | full coverage | nothing — but see constraint 1: this is the only option that **requires a module change** to ship at all |

## Choice B — which workspace receives Traffic Analytics

Constraint 3 applies to all three: whichever workspace is chosen, two new
outputs are needed to describe it.

**B1 — the `management-baseline` workspace, via a `count`-gated remote-state
read.** Extends [decision 0003](0003-management-baseline-promotion.md)'s
already-ratified `wire_management_workspace` mechanism, which today exists
**only in the corpus**
(`factory/templates/terraform/live/platform-connectivity/main.tf.tmpl:35-76`)
and **not in the live tree** — live connectivity still takes
`var.log_analytics_workspace_id` as a manual paste
(`terraform/live/platform-connectivity/main.tf:47`). Honours
[contract #4](../CROSS-DOMAIN-CONTRACTS.md#4-deliberately-unmapped-variables)
exactly as written: the workspace stays out of the schema and the wizard.
Flow data lands beside every other platform signal, so an investigation can
join flows against Defender, firewall and diagnostic logs in one query.
Cost: one workspace's fixed overhead, already being paid.

**B2 — a dedicated flow-logs workspace.** Isolates a noisy, high-volume,
low-value-per-row data set from the platform workspace, and lets flow
retention be tuned independently of platform-log retention. Also lets the
workspace be pinned to a residency boundary that differs from the platform
workspace's. Costs: a second workspace to provision, secure, retain and pay
fixed overhead on; a **split investigation surface** — the one query an
analyst most wants ("show me the firewall verdict and the flow for this
IP") now spans two workspaces; and a new schema/wizard question, or another
deliberately-unmapped variable, to say where it lives.

**B3 — an operator-supplied workspace resource ID.** The live tree's current
mechanism for connectivity: a variable, pasted after platform-management's
first apply. Zero new machinery. But decision 0003 **explicitly retired**
this pattern ("the manual resource-ID paste is retired"), and reinstating it
for a second consumer re-opens a wound that record closed — now three
pasted values per layer instead of one, since constraint 3 needs a triple.

## Choice C — which stack hosts the module call

| | Host | Reach | Storage accounts | Verdict |
| --- | --- | --- | --- | --- |
| **C1** | `platform-connectivity` | **hub NSGs only** — constraint 2 makes spoke NSGs in workload subscriptions unreachable without a module alias change | 2 (one per region) | Cannot deliver A1/A2/A4 as the module stands. Viable only for A3. |
| **C2** | Per-workload stack (`workloads-prod`, and `workloads-nonprod` in the corpus) | every spoke NSG in that subscription | one per `(region, environment)` — 2 for `workloads-prod` (`scus`/`prod`, `ncus`/`prod`); 2 for corpus `workloads-nonprod` if `environment = "nonprod"` is passed once per region | **Only option that reaches spoke NSGs today.** Constraint 1 is satisfied provided the call is made once per region at the stack level, not once per spoke module. |
| **C3** | `platform-management` | neither hub nor spoke NSGs — wrong subscription for both, plus the layer owns no network | — | Not viable. The workspace lives here; the flow logs cannot. |

The regional facts drive this more than preference: flow logs are per-NSG,
but Network Watcher and the storage account are **regional and
per-subscription**. A per-workload call does *not* multiply storage accounts
if it is made once per region in the stack (2 accounts), but it *does*
multiply them if it is made once per spoke module (constraint 1 would then
fail on the name collision between same-region same-environment spokes). A
central call needs cross-subscription reach the module does not have.

---

## Cost

**Method note, stated plainly.** Live list-price lookup was **not available
in this session**: the Azure MCP `pricing` tool and direct calls to
`prices.azure.com` were both refused by the environment's egress policy (403
at the proxy). The `azure-cost` skill's query/forecast workflows need an
authenticated estate, which does not exist yet (REVIEW.md §1). Every dollar
figure below is therefore a **list-price estimate built from stated
assumptions**, not a quote, and **re-verifying the per-GB rates is a
ratification prerequisite** — the same standing weakness REVIEW.md §17
already records for module-README cost tables.

### The meter structure (this part is not an assumption)

Four meters bill, in this order:

1. **Flow-log collection** — Network Watcher charges per GB of v2 flow logs
   collected.
2. **Traffic Analytics processing** — charged per GB of flow data processed;
   the rate depends on `traffic_analytics_interval`.
3. **Log Analytics ingestion** — the processed result lands in the workspace
   as `AzureNetworkAnalytics_CL` and is billed as workspace ingestion per GB.
4. **Blob storage** — the raw logs, retained `flow_log_retention_days`.

Plus two `azurerm_monitor_scheduled_query_rules_alert_v2` rules, billed per
rule per month.

**The dominant term is (1)+(2)+(3), and all three are per-GB.** Which is why
choice A moves cost far less than it appears to: adding the `pe` NSG adds
private-endpoint flows, which are a small fraction of spoke volume.

### Assumed rates

> **Assumption**, unverified this session, US region list price:
> collection ≈ **$0.50/GB**; Traffic Analytics processing at the 60-minute
> interval ≈ **$2.00/GB**; Log Analytics pay-as-you-go analytics ingestion ≈
> **$2.76/GB**. Combined ≈ **$5.25/GB**, and the honest band is **$4–$6/GB**.
> Blob Standard hot RA-GZRS ≈ **$0.05/GB-month** plus transactions.
> Scheduled-query alert rules ≈ **low single-digit dollars per rule-month**
> at the module's `PT5M` evaluation frequency.

> **Assumption** on volume, which is the figure that actually decides the
> bill and which nobody can know before the estate carries traffic. Three
> scenarios for the whole A2 estate (6 live NSGs), stated as monthly
> flow-log GB: **Quiet 2 GB** (a freshly-provisioned landing zone with
> little real traffic), **Typical 25 GB**, **Busy 150 GB**.

### Estimated monthly cost, A2 scope, 60-minute interval

| Scenario | Volume | Pipeline (≈$5.25/GB) | Storage (90-day steady state ≈ 3× monthly volume) | Alerts | **Total** |
| --- | --- | --- | --- | --- | --- |
| Quiet | 2 GB | ≈ $11 | ≈ $0.30 | ≈ $2–5 | **≈ $15/mo** |
| Typical | 25 GB | ≈ $131 | ≈ $4 | ≈ $2–5 | **≈ $140/mo** |
| Busy | 150 GB | ≈ $788 | ≈ $23 | ≈ $2–5 | **≈ $815/mo** |

Levers, in order of size:

- **`traffic_analytics_interval` 10 vs 60 is a real multiplier.** The 10-minute
  interval is billed at a materially higher per-GB processing rate —
  *assumption: roughly 2×* — which on the Typical scenario is **≈ +$50/mo**
  and on Busy **≈ +$300/mo**, for a latency improvement that only matters to
  a live SOC. This estate has none: `sentinel-siem` is a render-blocked
  scaffold (REVIEW.md §14). **Keep 60.**
- **`enable_traffic_analytics = false`** removes meters (2) and (3) entirely
  — roughly **90% of the bill** — leaving raw logs in blob storage that
  nothing queries and no alert rule can evaluate (both rules query
  `AzureNetworkAnalytics_CL`, and the module correctly `count`-gates them on
  the same flag). This is the cheap option and it is close to worthless.
- **`flow_log_retention_days` 90** costs almost nothing in this model —
  storage is 3% of the bill even in the Busy scenario. Shortening it saves
  no meaningful money and loses the 90-day investigation window. **Keep 90.**
- **NSG scope (choice A)** is a *weak* cost lever, per the above.

### The repository's own cost claims are wrong and should be corrected

Two artifacts state costs today and neither survives contact with the model:

- `terraform/modules/nsg-flow-logs/README.md` claims **"~$200/month"** total
  for 5 NSGs — a single number for a volume-driven meter. It happens to sit
  inside the band for the Typical scenario and is badly wrong for both
  others.
- The module's `estimated_monthly_cost_usd` output (`outputs.tf`) computes
  `storage = length(var.nsg_ids) * var.flow_log_retention_days * 0.15` and
  `traffic_analytics = 100` flat. The storage term is **dimensionally
  meaningless** — NSG-count × days × $0.15 has no unit basis — and yields
  ≈ $81/month for the A2 estate against a real figure nearer $4. The Traffic
  Analytics term ignores volume, the only thing that drives it. **This
  output ships into every generated repository**, where a client will read
  it as a number their landing zone produced.

(For the record, `site/app.js:121`'s `nsgFlowLogsPerRegion: 8` is **not** a
cost figure — that weights table counts Terraform resource blocks. It is
correct for what it does and is not implicated here.)

---

## Data residency

The second named driver, and the one that can veto an otherwise-fine option.

- **Raw flow logs stay in the NSG's region — mostly.** The storage account is
  created in `var.location`, which is the NSG's region. But
  `main.tf:10` hardcodes `account_replication_type = "RAGZRS"` **with no
  variable to change it**, so every flow log is asynchronously replicated to
  the Azure **paired region** and is readable there. For a US estate
  (`scus` ↔ `ncus`) that is in-country and unremarkable. For an engagement
  under an EU/UK data boundary or a single-country sovereignty commitment,
  **RA-GZRS moves network metadata across the boundary with no opt-out short
  of a module change.** The module's README advertises geo-redundancy as a
  feature; for some clients it is a defect.
- **Traffic Analytics moves data to the workspace's region, not the NSG's.**
  `management-baseline` provisions one workspace, in the primary region. Under
  B1, DR-region (`ncus`) flow data is processed into a `scus` workspace.
  Flow-log records are network metadata — source and destination IPs, ports,
  protocol, byte and packet counts, allow/deny verdict — and in many regimes
  IP addresses are personal data. A cross-region workspace is therefore a
  disclosable data flow even though no payload crosses.
- **`log_analytics_workspace_region` is the knob that records this.** It is a
  required input precisely because Traffic Analytics needs to be told where
  the workspace is; treating it as a residency declaration rather than a
  plumbing value is the right posture, and it should be surfaced in the
  generated observability documentation.
- **B2's one genuine advantage** is here: a dedicated workspace can be pinned
  to a residency boundary that the platform workspace does not respect. If a
  future engagement is boundary-constrained *and* wants a single platform
  workspace elsewhere, B2 becomes the right answer for that engagement.

---

## Decision

**This is a recommendation, not a decision. Ratification is the operator's
call and the [REVIEW.md](../../REVIEW.md) §11 gate stays closed until it
happens.**

Recommended: **A2 (all three spoke NSGs) + B1 (the `management-baseline`
workspace via a `count`-gated remote-state read) + C2 (per-workload stack,
one module instance per region)** — shipped behind a new
`enable_nsg_flow_logs` boolean defaulting to **`false`**, flipped in a later
PR, exactly as decision 0003 shipped `wire_management_workspace`.

**Why A2 beats A1**, honestly: A1 is not meaningfully cheaper. Cost tracks
traffic volume, and private-endpoint subnets are destinations for
comparatively small flows, so excluding the `pe` NSG saves a rounding error.
What it costs is the flow record for every private-endpoint connection —
which is the single most useful record when investigating whether data left
through a PaaS endpoint. Paying near-nothing to keep the exfiltration path
visible is not a close call. A1 remains the right answer only if the
`pe`-subnet flows turn out to be unexpectedly voluminous in practice, which
is measurable after one month and reversible by editing one map entry.

**Why A2 beats A4**, which is the more interesting runner-up: A4 is strictly
better coverage and it is the option this paper would recommend if the module
allowed it. Constraint 1 blocks it — a connectivity-hosted call and the
workloads-prod primary call collide on the global storage-account name
`stflowlogsscusprod`. Shipping A4 therefore means changing the module's name
scheme in both trees *before* any flow log is collected, which converts a
wiring change into a module change and delays all coverage for the sake of
the NSG that **does not exist in an Azure Firewall estate at all**. Hub
coverage is a follow-up, not a blocker.

**Why B1 beats B2 and B3**: B1 is the only option that adds no new
mechanism. Decision 0003 already ratified the `count`-gated remote-state read
and contract #4 already records that the workspace never travels through
`lz-config.json`; B1 is that mechanism reaching one layer further. B2 buys
residency independence nobody has asked for yet, at the price of a second
workspace's fixed cost and a split investigation surface — the wrong trade
until an engagement's boundary actually demands it, at which point B2 is a
per-engagement override rather than the default. B3 reinstates the manual
paste decision 0003 retired, and now needs three pasted values rather than
one.

The honest cost of B1: it extends `wire_management_workspace` into the
**live** tree, closing the corpus↔live asymmetry the module inventory
exposed. That is a real scope expansion beyond "wire one module", and the
operator should ratify it knowingly rather than discover it in the diff.

**Why C2**: constraint 2 leaves no alternative that reaches a spoke NSG.

### Implementation sketch, if ratified

Nothing below is done. It is what ratification would authorise.

1. **Module outputs, both trees** (`terraform/modules/` and
   `factory/templates/terraform/modules/`, kept at parity):
   - `spoke-network/outputs.tf`: `nsg_ids` as a `map(string)` keyed by
     `app`/`data`/`pe`, so the caller passes one value rather than three.
   - `management-baseline/outputs.tf`: `log_analytics_workspace_guid`
     (the `workspace_id` attribute) and `log_analytics_workspace_location`.
     **Do not** rename or repurpose the existing `log_analytics_workspace_id`
     — the connectivity layer and the corpus remote-state read both consume
     it as the full ARM ID (constraint 3).
   - `hub-network/outputs.tf`: defer, with A2. It gains `fw_mgmt` NSG output
     only when hub coverage ships.
2. **Workspace chain, avoiding a second remote-state read.** `workloads-prod`
   already reads `terraform_remote_state.connectivity`. Rather than adding a
   platform-management read there, have **connectivity re-export the workspace
   triple** it receives, and have `workloads-prod` take it from the read it
   already performs. That in turn means the live connectivity layer picks up
   the corpus's `wire_management_workspace` `count`-gated read (mirroring
   `main.tf.tmpl:35-76`), which is the parity work named above.
3. **The call**, in `terraform/live/workloads-prod/main.tf` and the
   corresponding `.tmpl` — **two instances, one per region**, each
   `count`-gated on `var.enable_nsg_flow_logs`, each passing the merged
   `nsg_ids` of that region's spoke, `environment = "prod"`, the region's
   `region_code`, the spoke's `resource_group_name`, and the workspace
   triple. Mirror in `workloads-nonprod.tmpl` with `environment = "nonprod"`
   so the three nonprod spokes in a region share one instance (constraint 1).
4. **`enable_private_endpoint = false` initially**, stated in the call as a
   knowing posture reduction with a follow-up to add
   `privatelink.blob.core.windows.net` (constraint 4). The storage account is
   already `default_action = "Deny"`; the private endpoint is defence in
   depth, not the only control.
5. **Default-off flag, flipped later** — the decision-0003 shape, and it is
   the right shape here for the same reason and one more: the generated plan
   workflow plans every layer on every PR, so an ungated
   `data.azurerm_network_watcher` read would make the **first PR in every
   generated repository fail red** wherever `NetworkWatcherRG` does not yet
   exist, and `try()` cannot rescue a provider read — only `count` can.
6. **Schema and wizard**: map `security.nsgFlowLogs.enabled` →
   `enable_nsg_flow_logs`, `retentionDays` → `flow_log_retention_days`, and
   `trafficAnalytics` → `enable_traffic_analytics` in
   `factory/renderer/variable-map.json`, so the three keys the wizard already
   collects stop being discarded. Bounds check against
   [contract #7](../CROSS-DOMAIN-CONTRACTS.md#7-validation-bounds-ordering-wizard--schema--terraform):
   schema `retentionDays` is 1–365 and the Terraform variable is unbounded,
   so wizard ⊂ schema ⊂ Terraform holds with no edit. **Do not** add a
   workspace key — contract #4 forbids it.
7. **Correct the cost claims** in the module README and replace or delete
   `estimated_monthly_cost_usd`, in both trees.
8. **Curator pass**: REVIEW.md §11, TODO.md item 2.3, CHANGELOG.md, and the
   contract register — deliberately not done in this authoring pass beyond
   recording that the paper exists.

## Consequences

*(Of the recommended option, if ratified.)*

- **Positive**: the wizard's `security.nsgFlowLogs` answers acquire a
  consumer, so a promise the product already makes starts being kept; every
  spoke NSG including the private-endpoint path is logged; no new workspace,
  no new schema key, no contract #4 change; the mechanism is one already
  ratified in decision 0003; the flag defaults off, so the change is inert
  until a PR flips it and the first plan in every generated repo stays green;
  cost at the Quiet scenario is ≈$15/month, which is a defensible default to
  hand a client.
- **Negative**: hub/NVA management traffic stays unlogged until the module's
  storage-account naming is made overridable; `enable_private_endpoint` is
  knowingly set to `false`, weakening a posture the module README advertises;
  the private endpoint and the hub coverage both become follow-ups that can
  be forgotten; the live tree gains the `wire_management_workspace` read it
  did not previously carry, which is scope beyond the TODO item's wording;
  the RA-GZRS replication remains unconfigurable, so a residency-constrained
  engagement is still blocked; and the per-GB rates underpinning every figure
  here are unverified.
- **Follow-ups** (only after ratification): (a) make
  `account_replication_type` a variable defaulting to `RAGZRS`, so residency
  becomes a knob rather than a module fork; (b) make the storage account name
  overridable and then extend coverage to `fw_mgmt` (choice A4); (c) add
  `privatelink.blob.core.windows.net` and turn the private endpoint back on;
  (d) refresh the assumed rates against `prices.azure.com` from an
  environment with egress, and fold the result into REVIEW.md §17's periodic
  review.

## Open questions for the operator

1. **Residency**: is any near-term engagement under a data boundary that
   RA-GZRS replication or a cross-region workspace would violate? A "yes"
   moves the recommendation from B1 to B2 and promotes follow-up (a) ahead of
   the wiring.
2. **Volume**: is there any prior estate whose flow-log volume can anchor the
   Quiet/Typical/Busy assumption? Every figure in the cost section is
   downstream of that guess.
3. **Default posture in generated repos**: should `enable_nsg_flow_logs`
   render `false` for every client (the recommendation, matching
   `wire_management_workspace`), or should it render from
   `security.nsgFlowLogs.enabled` — which the wizard pre-checks — and so be
   **on by default** for clients who never touched the box? The second is
   more honest to what the wizard says and commits every client to a
   volume-driven bill they did not price.
4. **Scope expansion**: is extending `wire_management_workspace` into the live
   tree acceptable inside this item, or should it be split into its own item
   so TODO 2.3 stays "wire one module"?
5. **The bad cost output**: delete `estimated_monthly_cost_usd` or replace it
   with a documented per-GB formula? Deleting removes a number clients will
   otherwise trust; replacing keeps a number that is still only as good as
   the volume assumption behind it.
