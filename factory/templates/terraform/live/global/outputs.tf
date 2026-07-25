output "management_group_ids" {
  description = "Management group IDs"
  value       = module.management_groups.management_group_map
}

output "policy_assignments" {
  description = "Policy assignment IDs"
  value       = module.policy_baseline.policy_assignments
}
