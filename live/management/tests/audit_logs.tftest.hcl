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
