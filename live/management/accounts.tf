locals {
  # Member accounts and the top-level OU each one sits in. Accounts are created only when
  # needed; the environment accounts (test, qa, demo) come later (M3).
  accounts = {
    security  = "Management"
    workforce = "Development"
  }

  email_local  = split("@", var.account_email_base)[0]
  email_domain = split("@", var.account_email_base)[1]
}

# Closing an account takes 90 days and its email stays tied to it, so creation is applied
# locally after the maintainer's explicit yes (IAT-31) and a destroy is blocked.
resource "aws_organizations_account" "this" {
  for_each = local.accounts

  name      = each.key
  email     = format("%s+%s@%s", local.email_local, each.key, local.email_domain)
  parent_id = aws_organizations_organizational_unit.this[each.value].id

  # No billing access for IAM users; OrganizationAccountAccessRole stays as break-glass.
  iam_user_access_to_billing = "DENY"
  close_on_deletion          = false

  lifecycle {
    prevent_destroy = true
    # The Organizations API cannot change the email of a member account, and billing access
    # is changed only by the root user: drift in these is hidden, check billing access by hand.
    ignore_changes = [email, iam_user_access_to_billing, role_name]
  }
}
