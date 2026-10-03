mock_provider "aws" {}

# A mock provider cannot import: the imported budget, service-linked role and hand-made SCP are
# overridden. Their configured attributes (name, description, content) stay those of the
# configuration, which is what these runs pin to what exists in the account.
override_resource {
  target = module.budget.aws_budgets_budget.this
}

override_resource {
  target = aws_iam_service_linked_role.cloudtrail
}

override_resource {
  target = aws_organizations_policy.deny_leave_and_close_account
}

override_resource {
  target = aws_organizations_policy_attachment.root_deny_leave_and_close_account
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

# Literal IDs for the units, in the format the provider validates for the accounts' parents.
override_resource {
  target = aws_organizations_organizational_unit.this["Management"]
  values = { id = "ou-ab12-mgmt0001" }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Environments"]
  values = { id = "ou-ab12-envs0001" }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Development"]
  values = { id = "ou-ab12-devl0001" }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Operations"]
  values = { id = "ou-ab12-oper0001" }
}

variables {
  region             = "eu-south-1"
  root_id            = "r-ab12"
  account_email_base = "owner@example.com"
  budget_alert_email = "alerts@example.com"
}

run "the_default_is_the_current_stage_and_only_that" {
  command = apply

  assert {
    condition = toset(keys(aws_organizations_policy_attachment.scp)) == toset([
      "Development/deny-disable-cloudtrail",
      "Development/deny-leave-organization",
      "Development/deny-outside-allowed-region",
      "Development/deny-root-user",
    ])
    error_message = "The default is stage one: exactly the four baseline policies on Development, nothing on any other unit."
  }
}

run "nothing_is_attached_when_the_stage_is_emptied" {
  command = apply

  variables {
    scp_attachments = {}
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.scp) == 0
    error_message = "An empty stage must attach no baseline SCP."
  }
}

run "the_four_baseline_policies_exist_without_being_attached" {
  command = apply

  assert {
    condition     = toset(keys(nonsensitive(module.scp_baseline.policy_ids))) == toset(["deny-disable-cloudtrail", "deny-leave-organization", "deny-outside-allowed-region", "deny-root-user"])
    error_message = "The stack must create exactly the four baseline SCPs."
  }
}

run "stage_one_attaches_the_four_policies_to_development_only" {
  command = apply

  variables {
    scp_attachments = {
      Development = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
    }
  }

  assert {
    condition = toset(keys(aws_organizations_policy_attachment.scp)) == toset([
      "Development/deny-disable-cloudtrail",
      "Development/deny-leave-organization",
      "Development/deny-outside-allowed-region",
      "Development/deny-root-user",
    ])
    error_message = "Stage one must attach exactly the four policies to Development."
  }

  assert {
    condition     = alltrue([for a in values(aws_organizations_policy_attachment.scp) : a.target_id == "ou-ab12-devl0001"])
    error_message = "Every attachment of stage one must target the Development unit of this stack."
  }

  assert {
    condition     = alltrue([for key, a in aws_organizations_policy_attachment.scp : a.policy_id == nonsensitive(module.scp_baseline.policy_ids)[split("/", key)[1]]])
    error_message = "Each attachment must carry the ID of the policy named in its key."
  }
}

run "every_stage_together_makes_sixteen_attachments_on_four_units" {
  command = apply

  variables {
    scp_attachments = {
      Development  = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
      Environments = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
      Operations   = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
      Management   = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
    }
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.scp) == 16
    error_message = "Four policies on four units make sixteen attachments."
  }

  assert {
    condition     = toset([for a in values(aws_organizations_policy_attachment.scp) : a.target_id]) == toset(["ou-ab12-mgmt0001", "ou-ab12-envs0001", "ou-ab12-devl0001", "ou-ab12-oper0001"])
    error_message = "The targets must be exactly the four units of this stack."
  }
}

run "no_attachment_targets_the_root_or_an_account" {
  command = apply

  variables {
    scp_attachments = {
      Development  = ["deny-leave-organization"]
      Environments = ["deny-root-user"]
      Management   = ["deny-outside-allowed-region"]
    }
  }

  assert {
    condition     = alltrue([for a in values(aws_organizations_policy_attachment.scp) : a.target_id != "r-ab12" && !can(regex("^[0-9]{12}$", a.target_id))])
    error_message = "A target must be an organizational unit of this stack: never the root, never an account."
  }
}

run "the_organization_root_cannot_be_named" {
  command = plan

  variables {
    scp_attachments = { Root = ["deny-root-user"] }
  }

  expect_failures = [var.scp_attachments]
}

run "an_account_cannot_be_named" {
  command = plan

  variables {
    scp_attachments = { "111122223333" = ["deny-root-user"] }
  }

  expect_failures = [var.scp_attachments]
}

run "an_unknown_policy_is_refused" {
  command = plan

  variables {
    scp_attachments = { Development = ["FullAWSAccess"] }
  }

  expect_failures = [var.scp_attachments]
}

run "a_policy_listed_twice_on_a_unit_is_refused" {
  command = plan

  variables {
    scp_attachments = { Development = ["deny-root-user", "deny-root-user"] }
  }

  expect_failures = [var.scp_attachments]
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

run "it_is_the_only_attachment_to_the_root" {
  command = plan

  variables {
    scp_attachments = {}
  }

  assert {
    condition     = aws_organizations_policy_attachment.root_deny_leave_and_close_account.target_id == "r-ab12"
    error_message = "The hand-made policy stays attached to the root."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.scp) == 0
    error_message = "With an empty stage no baseline SCP is attached, and never to the root."
  }
}
