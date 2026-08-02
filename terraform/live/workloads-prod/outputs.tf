# Adopted from the corpus workloads-prod outputs.tf.tmpl, de-tokenized: the
# live dogfood is always dual-region, so both outputs are unconditional.

output "primary_spoke_vnet_id" {
  description = "Production spoke VNet ID in the primary region"
  value       = module.spoke_prod_primary.spoke_vnet_id
}

output "dr_spoke_vnet_id" {
  description = "Production spoke VNet ID in the DR region"
  value       = module.spoke_prod_dr.spoke_vnet_id
}
