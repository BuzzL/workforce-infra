mock_provider "aws" {}

variables {
  allowed_region = "eu-south-1"
}

run "default_exceptions_are_exactly_the_documented_minimum" {
  command = plan

  assert {
    condition = jsondecode(aws_organizations_policy.this["deny-outside-allowed-region"].content) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "DenyOutsideAllowedRegion"
          Effect = "Deny"
          NotAction = [
            "account:*",
            "budgets:*",
            "ce:*",
            "iam:*",
            "identitystore:*",
            "organizations:*",
            "sso:*",
            "sts:*",
            "support:*",
          ]
          Resource  = "*"
          Condition = { StringNotEquals = { "aws:RequestedRegion" = ["eu-south-1"] } }
        }
      ]
    }
    error_message = "The region policy must be one Deny with NotAction over exactly the nine documented prefixes, conditioned on the region."
  }
}

run "region_and_exceptions_come_from_variables" {
  command = plan

  variables {
    allowed_region          = "eu-west-1"
    global_service_prefixes = ["iam", "organizations", "route53", "sts"]
  }

  assert {
    condition = jsondecode(aws_organizations_policy.this["deny-outside-allowed-region"].content).Statement == [
      {
        Sid       = "DenyOutsideAllowedRegion"
        Effect    = "Deny"
        NotAction = ["iam:*", "organizations:*", "route53:*", "sts:*"]
        Resource  = "*"
        Condition = { StringNotEquals = { "aws:RequestedRegion" = ["eu-west-1"] } }
      }
    ]
    error_message = "The region and the exceptions must come from the variables, with nothing added."
  }
}

run "a_malformed_region_is_rejected" {
  command = plan

  variables {
    allowed_region = "europe"
  }

  expect_failures = [var.allowed_region]
}

run "a_wildcard_or_action_in_a_prefix_is_rejected" {
  command = plan

  variables {
    global_service_prefixes = ["iam:*"]
  }

  expect_failures = [var.global_service_prefixes]
}

run "an_empty_exception_list_is_rejected" {
  command = plan

  variables {
    global_service_prefixes = []
  }

  expect_failures = [var.global_service_prefixes]
}

run "dropping_a_lockout_critical_prefix_is_rejected" {
  command = plan

  variables {
    global_service_prefixes = ["iam", "organizations"]
  }

  expect_failures = [var.global_service_prefixes]
}

run "duplicate_prefixes_are_rejected" {
  command = plan

  variables {
    global_service_prefixes = ["iam", "iam", "organizations", "sts"]
  }

  expect_failures = [var.global_service_prefixes]
}
