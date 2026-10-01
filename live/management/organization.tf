locals {
  # The four top-level units described in the workspace CLAUDE.md. Accounts are placed in
  # them by later stacks.
  organizational_units = toset(["Management", "Environments", "Development", "Operations"])
}

resource "aws_organizations_organizational_unit" "this" {
  for_each = local.organizational_units

  name      = each.key
  parent_id = var.root_id
}
