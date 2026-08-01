resource_group_name  = "rg-tfstate-scus-prod-01"
storage_account_name = "<REPLACE_WITH_OUTPUT_FROM_BOOTSTRAP>"
container_name       = "global-mgmt-groups"
key                  = "terraform.tfstate"

use_azuread_auth     = true
