# The baseline of the quality account: the GitHub OIDC provider and the two CI roles
# (modules/account-ci-baseline). It is applied locally, like bootstrap/, so that CI can never
# widen its own role: the stack CI applies is live/environments/quality (docs/ACCOUNT_CI_BASELINES.md).
locals {
  # Same key as the backend: CI passes -backend-config=key=<stack>/terraform.tfstate.
  state_key      = "bootstrap/accounts/quality/terraform.tfstate"
  live_state_key = "live/environments/quality/terraform.tfstate"
}

module "baseline" {
  source = "../../../modules/account-ci-baseline"

  account_name       = "quality"
  apply_role_name    = "qual-foundation-infra-role"
  plan_role_name     = "qual-foundation-infra-plan-role"
  role_path          = "/platform/"
  state_bucket_name  = var.state_bucket_name
  state_key          = local.live_state_key
  baseline_state_key = local.state_key
  tags               = var.tags
}
