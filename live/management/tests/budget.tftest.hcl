mock_provider "aws" {}

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

# The import itself is only proven by a real plan against the account (the resource is
# overridden here, a mock provider cannot import); these runs prove the wiring.
# The budget is imported, not recreated: the name and limit below are those of the
# budget that exists in the account, asserted literally so that changing either is a
# visible, reviewed change to this file.

run "imports_the_existing_budget_with_its_limit" {
  command = plan

  assert {
    condition     = module.budget.name == "Workforce Budget"
    error_message = "The stack must manage the budget named Workforce Budget."
  }

  assert {
    condition     = module.budget.limit_usd == 20
    error_message = "The monthly limit must be 20 USD."
  }
}

run "the_alert_address_comes_from_the_variable" {
  command = plan

  variables {
    budget_alert_email = "someone@example.org"
  }

  assert {
    condition     = [for e in nonsensitive(module.budget.alert_emails) : nonsensitive(e)] == ["someone@example.org"]
    error_message = "The module must be given exactly the address passed in budget_alert_email."
  }
}

run "alert_address_must_look_like_an_email" {
  command = plan

  variables {
    budget_alert_email = "not-an-email"
  }

  expect_failures = [var.budget_alert_email]
}
