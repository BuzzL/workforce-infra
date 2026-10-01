locals {
  # Same key as the backend: CI passes -backend-config=key=<stack>/terraform.tfstate.
  state_key = "live/accounts/security/terraform.tfstate"
}

module "baseline" {
  source = "../../../modules/account-ci-baseline"

  account_name      = "security"
  state_bucket_name = var.state_bucket_name
  state_key         = local.state_key
  tags              = var.tags
}
