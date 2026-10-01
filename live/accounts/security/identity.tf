# Identity Center, administered here as the delegated administrator (bootstrap/identity.tf).
# The management account is not assigned from here: Identity Center cannot provision a
# permission set into it from a delegated administrator. For the same reason the sets get
# their own names and the manual AdministratorAccess set is never imported or touched: it is
# provisioned in the management account, which a delegated administrator cannot modify
# (docs/IDENTITY_CENTER.md).
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
    WorkforceAdministrator = {
      description        = "Full access, for changes. Short sessions."
      managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
      session_duration   = "PT4H"
    }
    WorkforceReadOnly = {
      description        = "Read only, for looking around."
      managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      session_duration   = "PT8H"
    }
  }

  assignments = {
    WorkforceAdministrator = local.assigned_accounts
    WorkforceReadOnly      = local.assigned_accounts
  }
}
