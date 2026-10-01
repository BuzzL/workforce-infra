mock_provider "aws" {}

variables {
  name         = "workforce-monthly"
  limit_usd    = 100
  alert_emails = ["alerts@example.com"]
}

# Thresholds are asserted literally on purpose: moving one must be a reviewed change here.

run "defaults_notify_at_50_80_100_percent_of_actual_spend" {
  command = plan

  assert {
    condition     = toset([for n in nonsensitive(aws_budgets_budget.this.notification) : tonumber(n.threshold)]) == toset([50, 80, 100])
    error_message = "The default thresholds must be exactly 50, 80 and 100."
  }

  assert {
    condition = alltrue([
      for n in nonsensitive(aws_budgets_budget.this.notification) :
      n.comparison_operator == "GREATER_THAN" && n.notification_type == "ACTUAL" && n.threshold_type == "PERCENTAGE"
    ])
    error_message = "Every notification must be a GREATER_THAN, ACTUAL, PERCENTAGE alert."
  }
}

run "every_notification_reaches_the_given_addresses" {
  command = plan

  variables {
    alert_emails = ["a@example.com", "b@example.com"]
  }

  assert {
    condition = alltrue([
      for n in nonsensitive(aws_budgets_budget.this.notification) :
      toset(n.subscriber_email_addresses) == toset(["a@example.com", "b@example.com"])
    ])
    error_message = "Each notification must go to exactly the addresses passed in."
  }
}

run "budget_is_monthly_cost_in_usd_with_the_given_limit" {
  command = plan

  variables {
    limit_usd = 42.5
  }

  assert {
    condition = (
      aws_budgets_budget.this.name == "workforce-monthly" &&
      aws_budgets_budget.this.budget_type == "COST" &&
      aws_budgets_budget.this.time_unit == "MONTHLY" &&
      aws_budgets_budget.this.limit_unit == "USD" &&
      aws_budgets_budget.this.limit_amount == "42.5"
    )
    error_message = "The budget must be a monthly USD cost budget with the limit from the variable."
  }
}

run "non_positive_limit_is_rejected" {
  command = plan

  variables {
    limit_usd = 0
  }

  expect_failures = [var.limit_usd]
}

run "malformed_email_is_rejected" {
  command = plan

  variables {
    alert_emails = ["not-an-email"]
  }

  expect_failures = [var.alert_emails]
}

run "no_email_is_rejected" {
  command = plan

  variables {
    alert_emails = []
  }

  expect_failures = [var.alert_emails]
}
