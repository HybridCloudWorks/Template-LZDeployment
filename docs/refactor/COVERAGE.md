# Refactor gate 5 — Placeholder / question coverage

Bidirectional guarantee: every placeholder in the output templates maps to an
answer-record field, and every mapped answer-record field is collected by a
wizard question. Enforced automatically in both directions:

- **Placeholder → field:** the token engine fails closed on any unknown
  configuration path at render time, and `Test-LzSchemaDrift` (Factory CI check
  "Schema variable drift") fails on a mapped config key with no Terraform
  variable **and** on a required Terraform variable no key feeds.
- **Field → question:** the wizard exports only what its bound inputs collect
  (`data-path`/`data-set`/repeaters); schema `additionalProperties: false`
  rejects any key the wizard did not declare; `factory/tests/test.js` asserts
  wizard option sets equal schema enums for the narrowed fields.
- **Orphan = failure:** an orphaned template is a Factory CI failure
  ("Template coverage"); a residual token is a render failure and a CI grep
  failure (PLACEHOLDERS.md).

## Terraform-consumed answers (from `factory/renderer/variable-map.json` 2.0.0)

| Placeholder (variable) | Answer-record field | UI question (step → label) | Required? |
| --- | --- | --- | --- |
| `management_subscription_id` (mgmt, global) | `azure.subscriptions.management` | Azure tenant → Management subscription | Yes |
| `connectivity_subscription_id` (global, conn) | `azure.subscriptions.connectivity` | Azure tenant → Connectivity subscription | Yes |
| `identity_subscription_id` (global) | `azure.subscriptions.identity` | Azure tenant → Identity subscription | No (empty places nothing) |
| `workload_prod_subscription_id` (global) | `azure.subscriptions.workloadProd` | Azure tenant → Prod workload subscription | Yes |
| `workload_nonprod_subscription_id` (global) | `azure.subscriptions.workloadNonProd` | Azure tenant → Non-prod workload subscription | No |
| `sandbox_subscription_id` (global) | `azure.subscriptions.sandbox` | Azure tenant → Sandbox subscription | No |
| `root_parent_management_group_id` (global) | `azure.managementGroups.rootId` | Azure tenant → Root management group | Yes (empty = tenant root) |
| `org_prefix` (mgmt, conn) | `organization.companyShortName` | Organization → Short name | Yes |
| `primary_region` / `primary_region_code` | `azure.primaryRegion` / `.primaryRegionCode` | Azure tenant → Primary region (+code) | Yes |
| `dr_region` / `dr_region_code` (conn) | `azure.drRegion` / `.drRegionCode` | Azure tenant → DR region (+code) | No |
| `log_retention_days` (mgmt) | `observability.logAnalytics.retentionDays` | Observability → Log Analytics retention | Yes (default 90) |
| `primary_hub_address_space` (conn) | `connectivity.hubSpoke.primaryHubAddressSpace` | Connectivity → Primary hub CIDR | Yes when model ≠ none |
| `dr_hub_address_space` (conn) | `connectivity.hubSpoke.drHubAddressSpace` | Connectivity → DR hub CIDR | No |
| `azfw_tier` (conn) | `connectivity.firewall.azfwTier` | Connectivity → Azure Firewall tier | Yes (default Standard) |
| `deploy_bastion` (conn) | `connectivity.bastion.enabled` | Connectivity → Azure Bastion | Yes (checkbox) |
| `deploy_vpn_gateway` (conn) | `connectivity.vpn.enabled` | Connectivity → Site-to-site VPN | Yes (checkbox) — **newly consumed by this refactor** |
| `deploy_expressroute_gateway` (conn) | `connectivity.expressRoute.enabled` | Connectivity → ExpressRoute | Yes (checkbox) — **newly consumed** |
| `deploy_private_dns` (conn) | `connectivity.privateDns.enabled` | Connectivity → Private DNS zones | Yes (checkbox) |
| `private_dns_zones` (conn) | `connectivity.privateDns.zones` | Connectivity → Zone list | No (defaults empty) |
| `availability_zones` (conn) | `connectivity.hubSpoke.availabilityZones` | Connectivity → Availability zones | Yes (default 1,2,3) |
| `default_tags` (mgmt, conn) | `naming.defaultTags` | Naming & tags → Default tags | Yes (guard G06 enforces policy-required coverage) |
| `state_resource_group_name` / `state_storage_account_name` / `state_container_name` (global) | `backend.azurerm.*` | State backend → RG / account / container | Yes |
| Backend `backend.hcl` tokens (per layer) | `backend.azurerm.*`, `azure.tenantId` | State backend + Azure tenant steps | Yes |
| Topology selection (`#{{IF computed.topologyIsHubSpoke}}`) | `connectivity.model` | Connectivity → Topology | Yes |
| `log_daily_quota_gb` (mgmt) | `observability.logAnalytics.dailyQuotaGb` | Observability → Daily ingestion cap | Yes (default -1, uncapped) |
| `firewall_enabled` (conn) | `connectivity.firewall.enabled` | Connectivity → Deploy an Azure Firewall | Yes — no default, the client must answer |
| `policy_assignment_changes` (global) | `governance.policySelection.groups` / `.assignments` via `computed.policyAssignmentChanges` | Policies → Capability groups + advanced list | No (empty = the library's own baseline) |
| `policy_assignment_management_groups` (global) | derived from `site/alz-policy-catalog.json` via `computed.policyAssignmentManagementGroups` | none — a library fact, not an answer | No |
| `architecture_name` (global) | `azure.managementGroups.strategy` + `.customHierarchy` via `computed.architectureName` | Azure tenant → Hierarchy strategy + Management group names | Yes (`alz` unless renamed) |
| `management_management_group_id` / `connectivity_` / `identity_` / `sandbox_` (global) | `azure.managementGroups.customHierarchy` via `computed.*ManagementGroupId` | Azure tenant → Management group names | Yes — emitted always, never defaulted |
| `workload_management_group_id` (global) | `azure.managementGroups.workloadPlacement` via `computed.workloadManagementGroupId` | Azure tenant → Workload subscription placement | Yes (default `corp`) |
| `ddos_protection_plan_id` (global) | `governance.policySelection.values.ddos_protection_plan_id` | Policies → DDoS protection plan resource ID | Yes when the DDoS group is on (guard G28) |
| `email_security_contact` (global) | `governance.policySelection.values.email_security_contact` | Policies → Defender for Cloud security contact | Yes when a Defender assignment is selected (guard G28) |

Defaulted-in-`variables.tf`, deliberately question-free (`literal:*` in the
map): `architecture_name` (`alz`), the five `*_management_group_id` placement
targets (pinned-library ids), and `hub_and_spoke_networks_settings` (escape
hatch, defaults `{}`).

`firewall_enabled` was on that list, as `literal:true`. It is not any more: it
and `deploy_bastion` are the two largest recurring line items the connectivity
layer can create, and neither carries a default in `variables.tf` or in the
schema. An unanswered one blocks export.

## Documentation-consumed and record-only answers

The wizard collects more than the Terraform surface. Non-Terraform answers are
**consumed by the generated documentation templates** (governance, finops,
operating model, identity, observability docs) and/or **preserved in the
committed answer record** (`lz-config.json`) — never silently dropped, and the
wizard warns wherever an answer is recorded-not-deployed:

| Answer group | Consumed by | Deployment status |
| --- | --- | --- |
| GitHub settings (`github.*`) | Broker (repo creation, branch protection, environments, OIDC identities) | Deployed by broker |
| Identity model (`identity.cicdIdentityModel`) | Broker identity plan | Deployed by broker |
| Environments + approvals | Broker environments; workflow matrix | Deployed by broker |
| Governance (`policyBaseline.requiredTags`, frameworks, locks) | `docs/governance.md` + guard G06 | Docs |
| `policyBaseline.enforcementMode` | `docs/governance.md`, **and** the deny-class assignments' `enforcement_mode` in the global layer | Deployed — audit emits `DoNotEnforce` for the 14 Deny/DenyAction assignments only; downgrading the DeployIfNotExists ones would stop remediation across the estate |
| `governance.policySelection` | `policy_assignment_changes` in the global layer, `docs/governance.md`, guard G28 | Deployed |
| `azure.managementGroups.customHierarchy` | The emitted ALZ architecture definition and the placement targets, `docs/governance.md`, guard G29 | Deployed — schema 3.0.0 reshaped it from a free-form tree with zero readers into a rename map (ADR 0022) |
| `azure.managementGroups.strategy` | Manifest inclusion of the architecture definition (`custom` only), `docs/governance.md` | Partly deployed — **`caf-minimal` and `caf-standard` emit byte-identical Terraform** (REVIEW §23) |
| Defender plans / Sentinel / Key Vault CMK | `docs/*, unmet-dependency report, answer record` | **Recorded-not-deployed (ADR 0017)** — wizard warns, guard G02/G03 warns |
| FinOps (cost center, budgets, exports) | `docs/finops.md` | Docs |
| Operations (team, escalation, break-glass) | `docs/operating-model.md`, identity matrix | Docs |
| Observability alerting/drift | `docs/observability.md` | Docs |
| Naming patterns (`naming.standard`, patterns, abbreviations) | Guard validation + docs; resource names inside AVM modules follow the modules' conventions | Docs (ADR 0017) |
| Deployment strategy / brownfield | Quarantined brownfield tooling (CLASSIFICATION UNRESOLVED-2) | Deferred |

## Operator-supplied placeholders (deliberately no question)

None remain in the AVM corpus. The bespoke corpus's `management_ip_ranges`
commented placeholder retired with the hub-network module; hub management-plane
exposure is now governed by the AVM modules' own defaults and ALZ policy.
