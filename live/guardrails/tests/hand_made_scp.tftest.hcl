mock_provider "aws" {}

# A mock provider cannot import: the two imported resources are overridden. Their configured
# attributes (name, description, content) stay those of the configuration, which is what these runs
# pin to the policy that exists in the account.
override_resource {
  target = aws_organizations_policy.deny_leave_and_close_account
}

override_resource {
  target = aws_organizations_policy_attachment.root_deny_leave_and_close_account
}

override_data {
  target = data.aws_organizations_organization.this
  values = {
    roots = [{ id = "r-ab12", arn = "arn:aws:organizations::111122223333:root/o-abcdef1234/r-ab12", name = "Root", policy_types = [] }]
  }
}

override_data {
  target = data.aws_organizations_organizational_units.root
  values = {
    children = [
      { id = "ou-ab12-devl0001", arn = "arn:aws:organizations::111122223333:ou/o-abcdef1234/ou-ab12-devl0001", name = "Development" },
    ]
  }
}

override_data {
  target = data.aws_organizations_policies.scp
  values = {
    ids = ["p-aaaa1111", "p-bbbb2222"]
  }
}

override_data {
  target = data.aws_organizations_policy.scp["p-aaaa1111"]
  values = {
    name        = "FullAWSAccess"
    description = "Allows access to every operation"
    type        = "SERVICE_CONTROL_POLICY"
    aws_managed = true
  }
}

override_data {
  target = data.aws_organizations_policy.scp["p-bbbb2222"]
  values = {
    name        = "DenyLeaveAndCloseAccount"
    description = "Prevents member accounts from leaving the organization and self closure"
    type        = "SERVICE_CONTROL_POLICY"
    aws_managed = false
  }
}

variables {
  region = "eu-south-1"
}

# The policy as it exists in the account, read with `aws organizations describe-policy`: asserted
# literally, so changing it is a visible, reviewed change to this file.
run "the_imported_policy_is_the_one_that_exists_in_the_account" {
  command = plan

  assert {
    condition = jsondecode(aws_organizations_policy.deny_leave_and_close_account.content) == {
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Deny"
        Action   = ["organizations:LeaveOrganization", "account:CloseAccount"]
        Resource = "*"
      }]
    }
    error_message = "The imported SCP must deny exactly LeaveOrganization and CloseAccount, as the hand-made policy does."
  }

  assert {
    condition     = aws_organizations_policy.deny_leave_and_close_account.name == "DenyLeaveAndCloseAccount" && aws_organizations_policy.deny_leave_and_close_account.description == "Prevents member accounts from leaving the organization and self closure" && aws_organizations_policy.deny_leave_and_close_account.type == "SERVICE_CONTROL_POLICY"
    error_message = "Name, description and type must match the existing policy, or the import would plan a change."
  }
}

run "it_is_the_only_attachment_to_the_root_and_nothing_else_is_attached_by_default" {
  command = plan

  assert {
    condition     = aws_organizations_policy_attachment.root_deny_leave_and_close_account.target_id == "r-ab12"
    error_message = "The hand-made policy stays attached to the root."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 0
    error_message = "The baseline SCPs are attached to no unit by default, and never to the root."
  }
}
