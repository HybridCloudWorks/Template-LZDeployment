locals {
  sandbox_tags_merged = merge(
    var.sandbox_tags,
    {
      managed_by = "terraform"
      module     = "sandbox"
    }
  )
}

resource "azurerm_resource_group" "sandbox" {
  count = var.create_sandbox_rg ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = local.sandbox_tags_merged

  lifecycle {
    prevent_destroy = false
  }
}
