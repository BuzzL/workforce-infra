mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }

  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-1111111111111111"]
      identity_store_ids = ["d-1111111111"]
    }
  }

  mock_data "aws_identitystore_user" {
    defaults = { user_id = "11111111-2222-3333-4444-555555555555" }
  }

  mock_resource "aws_ssoadmin_permission_set" {
    defaults = { arn = "arn:aws:sso:::permissionSet/ssoins-1111111111111111/ps-1111111111111111" }
  }
}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"

  maintainer_username    = "maintainer"
  assignment_account_ids = { security = "111122223333", workforce = "444455556666" }
}

run "wires_the_baseline" {
  command = apply

  assert {
    condition     = local.state_key == "live/accounts/security/terraform.tfstate"
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

run "identity_reads_are_read_only_and_literal" {
  command = apply

  assert {
    condition = alltrue([
      for s in local.identity_read_statements : s.Effect == "Allow" && alltrue([
        for a in s.Action : can(regex("^(sso:(Get|List|Describe)[A-Za-z]+|identitystore:(Describe|Get)[A-Za-z]+)$", a))
      ])
    ])
    error_message = "The identity reads of the CI roles must be Get, List and Describe actions only."
  }

  assert {
    condition     = jsonencode([for s in local.identity_read_statements : s.Sid]) == jsonencode(["ReadIdentityCenterInstances", "ReadIdentityCenterPermissionSets", "ReadMaintainerUser"])
    error_message = "The identity read statements are exactly the documented three."
  }

  # Only the resourceless reads may use *: the permission set statement is scoped to Identity Center ARNs.
  assert {
    condition     = alltrue([for r in local.identity_read_statements[1].Resource : startswith(r, "arn:aws:sso:::")])
    error_message = "Permission set reads must stay scoped to Identity Center ARNs."
  }

  assert {
    condition     = join(",", module.access.permission_set_names) == "AdministratorAccess,ReadOnlyAccess"
    error_message = "The stack must manage exactly AdministratorAccess and ReadOnlyAccess."
  }

  assert {
    condition     = join(",", module.access.assignment_keys) == "AdministratorAccess/security,AdministratorAccess/workforce,ReadOnlyAccess/security,ReadOnlyAccess/workforce"
    error_message = "The maintainer must get both sets on every listed account."
  }
}
