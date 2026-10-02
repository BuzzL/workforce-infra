# Organizational units by name. IDs are looked up, never committed.
data "aws_organizations_organization" "this" {}

data "aws_organizations_organizational_units" "root" {
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

locals {
  ou_ids = { for ou in data.aws_organizations_organizational_units.root.children : ou.name => ou.id }

  # One entry per OU and policy of the current stage.
  attachments = {
    for pair in flatten([
      for ou, policies in var.attachments : [for policy in policies : { ou = ou, policy = policy }]
    ]) : "${pair.ou}/${pair.policy}" => pair
  }
}

# The target is always an organizational unit found by name: never the root of the Organization,
# never an account. A typo in an OU name fails the plan instead of attaching nothing.
resource "aws_organizations_policy_attachment" "this" {
  for_each = local.attachments

  policy_id = module.scp_baseline.policy_ids[each.value.policy]
  target_id = local.ou_ids[each.value.ou]

  lifecycle {
    precondition {
      condition     = contains(keys(local.ou_ids), each.value.ou)
      error_message = "The organizational unit ${each.value.ou} does not exist under the root of the Organization."
    }
  }
}
