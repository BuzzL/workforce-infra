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

run "identity_reads_are_exactly_the_documented_ones" {
  command = apply

  # The whole list, literally: a new action or resource must be a visible change here.
  assert {
    condition = jsonencode(local.identity_read_statements) == jsonencode([
      {
        Sid      = "ReadIdentityCenterInstances"
        Effect   = "Allow"
        Action   = ["sso:ListInstances"]
        Resource = ["*"]
      },
      {
        Sid    = "ReadIdentityCenterPermissionSets"
        Effect = "Allow"
        Action = [
          "sso:DescribePermissionSet",
          "sso:GetInlinePolicyForPermissionSet",
          "sso:GetPermissionsBoundaryForPermissionSet",
          "sso:ListAccountAssignments",
          "sso:ListCustomerManagedPolicyReferencesInPermissionSet",
          "sso:ListManagedPoliciesInPermissionSet",
          "sso:ListPermissionSets",
          "sso:ListTagsForResource",
        ]
        Resource = ["arn:aws:sso:::instance/ssoins-*", "arn:aws:sso:::permissionSet/ssoins-*/ps-*", "arn:aws:sso:::account/*"]
      },
      {
        Sid      = "ReadMaintainerUser"
        Effect   = "Allow"
        Action   = ["identitystore:DescribeUser", "identitystore:GetUserId"]
        Resource = ["*"]
      },
    ])
    error_message = "The identity reads of the CI roles must be exactly the three documented read statements."
  }

  assert {
    condition     = join(",", module.access.permission_set_names) == "WorkforceAdministrator,WorkforceReadOnly"
    error_message = "The stack must manage exactly WorkforceAdministrator and WorkforceReadOnly, never the manual AdministratorAccess set."
  }

  assert {
    condition     = join(",", module.access.assignment_keys) == "WorkforceAdministrator/security,WorkforceAdministrator/workforce,WorkforceReadOnly/security,WorkforceReadOnly/workforce"
    error_message = "The maintainer must get both sets on every listed account."
  }
}

run "empty_maintainer_is_rejected" {
  command = plan

  variables {
    maintainer_username = ""
  }

  expect_failures = [var.maintainer_username]
}

run "management_account_is_rejected" {
  command = plan

  variables {
    assignment_account_ids = { management = "111122223333" }
  }

  expect_failures = [var.assignment_account_ids]
}
