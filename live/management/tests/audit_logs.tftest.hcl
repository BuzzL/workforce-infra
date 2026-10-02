mock_provider "aws" {}

# A mock provider cannot import: the imported budget is overridden instead.
override_resource {
  target = module.budget.aws_budgets_budget.this
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
