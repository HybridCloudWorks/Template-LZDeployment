# Variable declarations for the global (ALZ core) layer.
# This file is the contract the schema-drift check validates against; it is
# copied verbatim, never templated.

# Naming inputs. The ALZ library's policy default values include resource-group
# names and a region that policies write into resources they create; those are
# strings the policy carries, not references to resources that must already
# exist, so they are composed here rather than read back from a layer that
# applies after this one.

variable "org_prefix" {
  description = "Organization prefix used in resource names."
  type        = string
}

variable "primary_region_code" {
  description = "Short code for the primary region, used in resource names."
  type        = string
}

variable "architecture_name" {
  description = "ALZ library architecture to deploy. Must exist in the pinned library reference."
  type        = string
  default     = "alz"
}

variable "root_parent_management_group_id" {
  description = "Parent for the ALZ hierarchy. Empty deploys under the tenant root group."
  type        = string
  default     = ""
}

variable "primary_region" {
  description = "Primary Azure region for policy-managed deployments."
  type        = string
}

variable "management_subscription_id" {
  description = "Management subscription (also the provider's default subscription)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.management_subscription_id))
    error_message = "management_subscription_id must be a GUID."
  }
}

variable "connectivity_subscription_id" {
  description = "Connectivity subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "identity_subscription_id" {
  description = "Identity subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "workload_prod_subscription_id" {
  description = "Production workload subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "workload_nonprod_subscription_id" {
  description = "Non-production workload subscription. Empty places nothing."
  type        = string
  default     = ""
}

variable "sandbox_subscription_id" {
  description = "Sandbox subscription. Empty places nothing."
  type        = string
  default     = ""
}

# Management-group IDs for subscription placement. Defaults match the id set
# the pinned `alz` architecture defines; override only alongside a custom
# architecture definition.

variable "management_management_group_id" {
  description = "Management-group ID that receives the management subscription."
  type        = string
  default     = "management"
}

variable "connectivity_management_group_id" {
  description = "Management-group ID that receives the connectivity subscription."
  type        = string
  default     = "connectivity"
}

variable "identity_management_group_id" {
  description = "Management-group ID that receives the identity subscription."
  type        = string
  default     = "identity"
}

variable "landing_zones_management_group_id" {
  description = "Management-group ID that receives workload subscriptions."
  type        = string
  default     = "landingzones"
}

variable "sandbox_management_group_id" {
  description = "Management-group ID that receives the sandbox subscription."
  type        = string
  default     = "sandbox"
}

# Remote-state read of the platform-management layer.

variable "state_resource_group_name" {
  description = "Resource group of the state storage account."
  type        = string
}

variable "state_storage_account_name" {
  description = "State storage account."
  type        = string
}

variable "state_container_name" {
  description = "State container."
  type        = string
}

# Client policy selection. These two travel together and are rendered from the
# same source — the wizard's answers resolved against the generated policy
# catalog — so a name in one and not the other is a renderer defect, not a
# configuration the operator is expected to fix here.

variable "policy_assignment_changes" {
  description = <<-DESCRIPTION
    Deltas from the pinned library's own policy baseline, keyed by assignment
    name. Only assignments the client actually changed appear: an assignment
    with no entry is created exactly as the library declares it. creation_enabled
    = false means the assignment is never created, which is different from
    created and unenforced.
  DESCRIPTION
  type = map(object({
    creation_enabled = optional(bool)
    enforcement_mode = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for change in values(var.policy_assignment_changes) :
      change.enforcement_mode == null || contains(["Default", "DoNotEnforce"], change.enforcement_mode)
    ])
    error_message = "enforcement_mode must be Default or DoNotEnforce. Azure Policy rejects anything else at assignment time, long after plan."
  }
}

variable "policy_assignment_management_groups" {
  description = <<-DESCRIPTION
    Assignment name -> the management groups that carry it, read from the ALZ
    archetype definitions at the pinned library ref. Most of the library's
    assignments are carried by more than one management group, and
    policy_assignments_to_modify is keyed by management group rather than by
    assignment, so this edge is what lets the layer invert one into the other.
  DESCRIPTION
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for scopes in values(var.policy_assignment_management_groups) : length(scopes) > 0])
    error_message = "Every assignment must name at least one management group. An empty list would silently drop the change."
  }
}

# Policy default values the client owns. Everything else the pinned ALZ library
# declares is composed by this layer from platform facts; these two are real
# answers about this estate, and the wizard refuses to export without them when
# an assignment that consumes one is selected.

variable "ddos_protection_plan_id" {
  description = "Existing DDoS Network Protection plan the Enable-DDoS-VNET assignment attaches to every virtual network. Empty when the DDoS capability group is off, in which case the assignment is never created."
  type        = string
  default     = ""

  validation {
    condition     = var.ddos_protection_plan_id == "" || can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Network/ddosProtectionPlans/[^/]+$", var.ddos_protection_plan_id))
    error_message = "Must be a full DDoS protection plan resource ID, or empty. Enable-DDoS-VNET is a Modify effect: a name that is not a resource ID is written onto every virtual network at create and update."
  }
}

variable "email_security_contact" {
  description = "Address Microsoft Defender for Cloud notifies, set by the Deploy-MDFC-Config-H224 assignment. Empty when no Defender assignment is selected."
  type        = string
  default     = ""

  validation {
    condition     = var.email_security_contact == "" || can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.email_security_contact))
    error_message = "Must be an email address, or empty. The library's own placeholder is security_contact@replace_me, which Defender accepts and then notifies nobody."
  }
}
