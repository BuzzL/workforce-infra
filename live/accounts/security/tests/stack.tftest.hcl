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
  region = "eu-west-1"

  maintainer_username    = "maintainer"
  assignment_account_ids = { security = "111122223333", workforce = "444455556666" }
}

run "identity_center_manages_exactly_the_documented_sets" {
  command = apply

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
