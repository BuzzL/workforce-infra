mock_provider "aws" {}

# A mock provider cannot import: the imported budget and service-linked role are overridden.
override_resource {
  target = module.budget.aws_budgets_budget.this
}

override_resource {
  target = aws_iam_service_linked_role.cloudtrail
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
}
