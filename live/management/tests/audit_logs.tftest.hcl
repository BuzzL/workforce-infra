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

run "the_trail_is_off_by_default" {
  command = plan

  assert {
    condition     = length(module.organization_trail) == 0
    error_message = "Without audit_log_bucket_name the stack must create no trail."
  }
}

run "the_trail_is_created_for_the_given_bucket_when_enabled" {
  command = plan

  variables {
    audit_log_bucket_name = "workforce-audit-logs-example"
  }

  assert {
    condition     = length(module.organization_trail) == 1 && module.organization_trail[0].name == "workforce-organization"
    error_message = "Setting audit_log_bucket_name must create the organization trail with its default name."
  }
}

run "an_empty_bucket_name_keeps_it_off" {
  command = plan

  variables {
    audit_log_bucket_name = ""
  }

  assert {
    condition     = length(module.organization_trail) == 0
    error_message = "An unset secret arrives as an empty string and must keep the trail off."
  }

  # The switch is not a secret: it must not carry the sensitivity of the bucket name.
  assert {
    condition     = !issensitive(local.audit_logging)
    error_message = "The on/off switch must not be sensitive while the trail is off."
  }
}
