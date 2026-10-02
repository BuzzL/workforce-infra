# DenyLeaveAndCloseAccount was created by hand in the console and attached to the root of the
# Organization before this stack existed. It denies member accounts leaving the Organization and
# closing themselves (organizations:LeaveOrganization, account:CloseAccount). The imports bring it
# and its root attachment under Terraform without recreating or changing them; once applied, the
# blocks are no-ops.
#
# This is the single, fixed exception to "never attach an SCP to the root": it is not driven by
# var.attachments, which can only name organizational units. prevent_destroy makes a plan that
# would delete or detach it fail. FullAWSAccess, also attached to the root, is AWS-managed and is
# never touched by this stack.
data "aws_organizations_policies" "scp" {
  filter = "SERVICE_CONTROL_POLICY"
}

# The data source lists IDs only: each SCP is read by ID and the hand-made one is found by name,
# so no policy ID is committed.
data "aws_organizations_policy" "scp" {
  for_each = toset(data.aws_organizations_policies.scp.ids)

  policy_id = each.value
}

# A clear failure when the hand-made policy is missing or renamed: otherwise the import id is null.
check "hand_made_scp_found" {
  assert {
    condition     = length([for id, p in data.aws_organizations_policy.scp : id if p.name == "DenyLeaveAndCloseAccount"]) == 1
    error_message = "Exactly one SCP named DenyLeaveAndCloseAccount must exist (it was created by hand and is imported here); none or several were found."
  }
}

locals {
  hand_made_policy_id = one([for id, p in data.aws_organizations_policy.scp : id if p.name == "DenyLeaveAndCloseAccount"])
  root_id             = data.aws_organizations_organization.this.roots[0].id
}

import {
  to = aws_organizations_policy.deny_leave_and_close_account
  id = local.hand_made_policy_id
}

import {
  to = aws_organizations_policy_attachment.root_deny_leave_and_close_account
  id = "${local.root_id}:${local.hand_made_policy_id}"
}

resource "aws_organizations_policy" "deny_leave_and_close_account" {
  name        = "DenyLeaveAndCloseAccount"
  description = "Prevents member accounts from leaving the organization and self closure"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = ["organizations:LeaveOrganization", "account:CloseAccount"]
      Resource = "*"
    }]
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_organizations_policy_attachment" "root_deny_leave_and_close_account" {
  policy_id = aws_organizations_policy.deny_leave_and_close_account.id
  target_id = local.root_id

  lifecycle {
    prevent_destroy = true
  }
}
