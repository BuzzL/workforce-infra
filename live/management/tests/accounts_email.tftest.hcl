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

variables {
  region             = "eu-west-1"
  root_id            = "r-ab12"
  account_email_base = "owner@example.com"
  budget_alert_email = "alerts@example.com"
}

# A separate file, so that it starts from an empty state: `ignore_changes = [email]` keeps
# the email of an existing account, so a new base only shows on an account being created.

run "emails_follow_a_changed_base" {
  command = apply

  variables {
    account_email_base = "boss@mail.example.org"
  }

  assert {
    condition     = aws_organizations_account.this["workforce"].email == "boss+workforce@mail.example.org"
    error_message = "No email may be hardcoded: it must follow account_email_base."
  }
}
