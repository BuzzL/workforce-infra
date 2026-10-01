# Identity Center is administered from the security account (IAT-33): permission sets and
# assignments live in live/accounts/security. Only the management account can delegate, and
# the registration changes who administers access, so it is applied here, locally, with SSO
# admin. It exists once the security account is in var.member_account_ids.
resource "aws_organizations_delegated_administrator" "identity_center" {
  count = contains(keys(var.member_account_ids), "security") ? 1 : 0

  account_id        = var.member_account_ids["security"]
  service_principal = "sso.amazonaws.com"
}
