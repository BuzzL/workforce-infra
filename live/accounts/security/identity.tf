# Identity Center, administered here as the delegated administrator (bootstrap/identity.tf).
# The management account is not assigned from here: Identity Center cannot provision a
# permission set into it from a delegated administrator (docs/IDENTITY_CENTER.md).
locals {
  # Account names are not secret, only their IDs: nonsensitive() lets them key for_each.
  assigned_accounts = sort(nonsensitive(keys(var.assignment_account_ids)))
}

module "access" {
  source = "../../../modules/identity-center-access"

  maintainer_username = var.maintainer_username
  account_ids         = var.assignment_account_ids
  tags                = var.tags

  permission_sets = {
    AdministratorAccess = {
      description        = "Full access, for changes. Short sessions."
      managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
      session_duration   = "PT4H"
    }
    ReadOnlyAccess = {
      description        = "Read only, for looking around."
      managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      session_duration   = "PT8H"
    }
  }

  assignments = {
    AdministratorAccess = local.assigned_accounts
    ReadOnlyAccess      = local.assigned_accounts
  }
}
