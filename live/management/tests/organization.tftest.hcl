mock_provider "aws" {}

override_resource {
  target = aws_organizations_organizational_unit.this["Management"]
  values = {
    id = "ou-ab12-mgmt0001"
  }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Environments"]
  values = {
    id = "ou-ab12-envs0001"
  }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Development"]
  values = {
    id = "ou-ab12-devl0001"
  }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Operations"]
  values = {
    id = "ou-ab12-ops00001"
  }
}

# A mock provider cannot import: the imported budget is overridden instead.
override_resource {
  target = module.budget.aws_budgets_budget.this
}

override_resource {
  target = aws_iam_service_linked_role.cloudtrail
}

# The hand-made root SCP is imported (service_control_policies.tf): a mock provider cannot import,
# so it is overridden, and the SCPs it is looked up among are faked.
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

variables {
  region             = "eu-west-1"
  root_id            = "r-ab12"
  account_email_base = "owner@example.com"
  budget_alert_email = "alerts@example.com"
}

# Values are asserted literally on purpose: a change to the OU names or their parent must
# be a visible, reviewed change to this file.

run "four_top_level_units_under_the_root" {
  command = apply

  assert {
    condition     = toset(keys(aws_organizations_organizational_unit.this)) == toset(["Management", "Environments", "Development", "Operations"])
    error_message = "The Organization must have exactly the OUs Management, Environments, Development and Operations."
  }

  assert {
    condition     = alltrue([for name, ou in aws_organizations_organizational_unit.this : ou.name == name && ou.parent_id == "r-ab12"])
    error_message = "Every OU must be named after its key and sit directly under the Organization root."
  }

  assert {
    condition     = toset(keys(output.organizational_unit_ids)) == toset(["Management", "Environments", "Development", "Operations"])
    error_message = "The output must list the four OUs by name."
  }
}

run "root_id_must_look_like_a_root_id" {
  command = plan

  variables {
    root_id = "ou-ab12-cdef5678"
  }

  expect_failures = [var.root_id]
}
