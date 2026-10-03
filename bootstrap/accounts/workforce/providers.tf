provider "aws" {
  region = var.region

  # Set only for the one-time bootstrap run locally: the provider then works inside the
  # member account through OrganizationAccountAccessRole (break-glass, see
  # docs/ACCOUNT_CI_BASELINES.md) while the state backend keeps using the caller's own
  # credentials. In CI this stays null and the OIDC role of the account is used directly.
  dynamic "assume_role" {
    for_each = var.break_glass_account_id == null ? [] : [var.break_glass_account_id]

    content {
      role_arn     = "arn:aws:iam::${assume_role.value}:role/OrganizationAccountAccessRole"
      session_name = "baseline-bootstrap"
    }
  }

  default_tags {
    tags = var.tags
  }
}
