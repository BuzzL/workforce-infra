mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
}

run "wires_the_baseline" {
  command = apply

  assert {
    condition     = local.state_key == "live/accounts/workforce/terraform.tfstate"
    error_message = "The state key must match the backend key CI derives from the stack path."
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
