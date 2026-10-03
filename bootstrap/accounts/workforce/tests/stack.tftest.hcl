mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

# A mock provider cannot import: every adopted resource (imports.tf) is overridden instead.
override_resource {
  target = module.baseline.aws_iam_openid_connect_provider.github
}

override_resource {
  target = module.baseline.aws_iam_role.apply
}

override_resource {
  target = module.baseline.aws_iam_role.plan
}

override_resource {
  target = module.baseline.aws_iam_role_policy.apply_state
}

override_resource {
  target = module.baseline.aws_iam_role_policy.apply_baseline_read
}

override_resource {
  target = module.baseline.aws_iam_role_policy.plan_state_read
}

override_resource {
  target = module.baseline.aws_iam_role_policy.plan_baseline_read
}

override_resource {
  target = module.baseline.aws_iam_role_policies_exclusive.apply
}

override_resource {
  target = module.baseline.aws_iam_role_policies_exclusive.plan
}

override_resource {
  target = module.baseline.aws_iam_role_policy_attachments_exclusive.apply
}

override_resource {
  target = module.baseline.aws_iam_role_policy_attachments_exclusive.plan
}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
}

run "wires_the_baseline" {
  command = apply

  # Its own key is the one CI derives from the stack path. The key of the stack that CI
  # applies is a different one: the apply role reaches that one and never this one.
  assert {
    condition     = local.state_key == "bootstrap/accounts/workforce/terraform.tfstate"
    error_message = "The state key must match the backend key CI derives from the stack path."
  }

  assert {
    condition     = local.live_state_key == "live/accounts/workforce/terraform.tfstate"
    error_message = "The apply role must reach the state of live/accounts/workforce."
  }

  assert {
    condition     = module.baseline.apply_role_arn != module.baseline.plan_role_arn
    error_message = "The apply and plan roles must be different roles."
  }
}

run "bootstrap_account_id_must_be_12_digits" {
  command = plan

  variables {
    break_glass_account_id = "not-an-id"
  }

  expect_failures = [var.break_glass_account_id]
}
