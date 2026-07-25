check "module_not_implemented" {
  assert {
    condition     = var.enable_module == false
    error_message = "terraform/modules/keyvault-cmk is scaffold-only and not implemented. Keep enable_module=false until full IaC resources are added."
  }
}
