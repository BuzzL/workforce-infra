locals {
  # One entry per organizational unit and policy of the current stage.
  scp_attachment_pairs = {
    for pair in flatten([
      for ou, policies in var.scp_attachments : [for policy in policies : { ou = ou, policy = policy }]
    ]) : "${pair.ou}/${pair.policy}" => pair
  }
}

# The target is always one of the organizational units this stack manages: never the root of the
# Organization, never an account. A stage is a change of the default of var.scp_attachments, so it
# is a reviewed PR, a plan in its comment and the approval of the `management` environment.
resource "aws_organizations_policy_attachment" "scp" {
  for_each = local.scp_attachment_pairs

  policy_id = module.scp_baseline.policy_ids[each.value.policy]
  target_id = aws_organizations_organizational_unit.this[each.value.ou].id

  lifecycle {
    precondition {
      condition     = contains(keys(aws_organizations_organizational_unit.this), each.value.ou)
      error_message = "The organizational unit ${each.value.ou} is not one this stack manages."
    }
  }
}
