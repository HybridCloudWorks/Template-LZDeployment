# Policy Baseline Module

## Overview

Deploys the landing zone's Azure Policy guardrails: custom policy definitions,
built-in policy assignments, and a TLS 1.2 enforcement initiative, scoped to
the management groups created by the `management-groups` module. Called by the
`global` layer (`terraform/live/global/main.tf`).

## What It Enforces

**Root management group (Deny)**
- `Require mandatory tags` — denies resources missing `owner`, `application`,
  `environment`, or `cost_center` tags (custom, `Indexed` mode)
- `Allowed locations` — built-in policy `e56962a6-4747-49cd-b67b-bf8b01975c4c`
  restricted to `var.allowed_locations`
- `Enforce TLS 1.2 Minimum Version` — custom initiative (see below), assigned
  with a system-assigned identity and a non-compliance message

**Platform management group (Audit)**
- `NSG should be associated with subnets` — built-in policy
  `e71308d3-144b-4262-b144-efdc3cc90517`

**Sandbox management group (Deny)**
- `Enforce environment=sandbox` tag on all resources
- `Require expiry_date tag` on all resources
- `Deny VNet peering` — preserves the sandbox air-gap

**TLS 1.2 initiative** (`policy-tls-minimum.tf`, all six with `Deny` effect,
parameterized `Audit`/`Deny`/`Disabled` per definition):

| Service | Resource type evaluated |
|---|---|
| Storage Accounts | `Microsoft.Storage/storageAccounts` (`minimumTlsVersion`) |
| App Service | `Microsoft.Web/sites/config` (`minTlsVersion`) |
| Function Apps | `Microsoft.Web/sites/config` (`minTlsVersion`, `kind like functionapp*`) |
| Azure Database for MySQL | `Microsoft.DBforMySQL/servers` (`minimalTlsVersion`) |
| Azure Database for PostgreSQL | `Microsoft.DBforPostgreSQL/servers` (`minimalTlsVersion`) |
| API Management | `Microsoft.ApiManagement/service` (`customProperties` legacy TLS 1.0/1.1 keys) |

## Usage

From `terraform/live/global/main.tf`:

```hcl
module "policy_baseline" {
  source = "../../modules/policy-baseline"

  root_mg_id        = module.management_groups.root_mg_id
  platform_mg_id    = module.management_groups.platform_mg_id
  sandbox_mg_id     = module.management_groups.sandbox_mg_id
  allowed_locations = var.allowed_locations

  depends_on = [module.management_groups]
}
```

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `root_mg_id` | Root management group resource ID | `string` | — | yes |
| `platform_mg_id` | Platform management group ID | `string` | — | yes |
| `sandbox_mg_id` | Sandbox management group ID | `string` | — | yes |
| `location` | Azure region for the policy assignment managed identity | `string` | `"southcentralus"` | no |
| `allowed_locations` | List of allowed Azure regions | `list(string)` | `["southcentralus", "northcentralus"]` | no |
| `landingzones_mg_id` | Landing Zones management group ID. Scope for workload-facing policy assignments. | `string` | `""` | no |
| `assign_public_network_access_policy` | Assign the initiative auditing (or denying) public network access on PaaS data services, scoped to the Landing Zones management group. | `bool` | `false` | no |
| `public_network_access_effect` | Effect for the public-network-access initiative: `Audit`, `Deny`, or `Disabled`. | `string` | `"Audit"` | no |

## Outputs

| Name | Description |
|---|---|
| `policy_assignments` | Map of policy assignment IDs (tags, locations, NSG audit, sandbox rules) |
| `tls_policy_initiative_id` | ID of the TLS 1.2 enforcement policy initiative |
| `tls_policy_assignment_id` | ID of the TLS 1.2 policy assignment |
| `policy_definitions` | Map of all TLS 1.2 policy definition IDs (storage, appservice, functionapp, mysql, postgresql, apim) |

## Cost Estimate

| Component | Monthly Cost (estimate) |
|---|---|
| Policy definitions, initiatives, assignments | $0 |
| **Total** | **$0/month** |

*Azure Policy definitions and assignments are free. Only add-on compliance
features outside this module (e.g., guest configuration) carry a charge.*

## Notes

- The Deny effects take hold at request time: existing non-compliant resources
  show as non-compliant but are not modified.
- The `require-mandatory-tags` deny at root applies to the state
  storage/bootstrap resources too — deploy `management-groups` and this module
  after `backend-bootstrap`, or ensure bootstrap resources carry the four
  mandatory tags.
- The APIM definition only catches *explicit* enablement of TLS 1.0/1.1
  (`customProperties`); services created after 2018-04-01 default those
  protocols to disabled.

## References

- [Azure Policy documentation](https://learn.microsoft.com/azure/governance/policy/overview)
- [Built-in policy: Allowed locations](https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies)
- [APIM customProperties (TLS protocol keys)](https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service)
