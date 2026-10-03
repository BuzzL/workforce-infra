mock_provider "aws" {}

# A mock provider cannot import: the imported budget and service-linked role are overridden.
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

# The import itself, and that destroying the role fails, are proven by a real plan against the
# account (a mock provider can neither import nor assert prevent_destroy). These runs pin what the
# configuration says: it is the CloudTrail service-linked role, and it sets nothing but the service.
run "manages_the_cloudtrail_service_linked_role" {
  command = plan

  assert {
    condition     = aws_iam_service_linked_role.cloudtrail.aws_service_name == "cloudtrail.amazonaws.com"
    error_message = "The stack must manage the service-linked role of cloudtrail.amazonaws.com."
  }
}

run "sets_no_attribute_the_apply_role_cannot_update" {
  command = plan

  # The apply role may tag the role and nothing else (no iam:UpdateRole): a description or a custom
  # suffix would plan an update, or a replacement, that CI could not apply.
  assert {
    condition     = aws_iam_service_linked_role.cloudtrail.custom_suffix == null
    error_message = "A custom suffix would replace the role: it must stay unset."
  }

  assert {
    condition     = aws_iam_service_linked_role.cloudtrail.description == null
    error_message = "A description would plan an iam:UpdateRole that the apply role cannot do: it must stay unset."
  }
}
