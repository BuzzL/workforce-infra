mock_provider "aws" {
  mock_resource "aws_ssoadmin_permission_set" {
    defaults = { arn = "arn:aws:sso:::permissionSet/ssoins-1111111111111111/ps-1111111111111111" }
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
}

variables {
  maintainer_username = "maintainer"
  account_ids         = { security = "111111111111", workforce = "222222222222" }

  permission_sets = {
    AdministratorAccess = {
      description        = "Full access, for changes."
      managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
      session_duration   = "PT4H"
    }
    ReadOnlyAccess = {
      description        = "Read only, for looking around."
      managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      session_duration   = "PT8H"
    }
  }

  assignments = {
    AdministratorAccess = ["security", "workforce"]
    ReadOnlyAccess      = ["security", "workforce"]
  }
}

run "permission_sets_carry_one_managed_policy_each" {
  command = apply

  assert {
    condition     = join(",", output.permission_set_names) == "AdministratorAccess,ReadOnlyAccess"
    error_message = "Expected exactly AdministratorAccess and ReadOnlyAccess."
  }

  assert {
    condition = (
      aws_ssoadmin_managed_policy_attachment.this["AdministratorAccess"].managed_policy_arn == "arn:aws:iam::aws:policy/AdministratorAccess"
      && aws_ssoadmin_managed_policy_attachment.this["ReadOnlyAccess"].managed_policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    )
    error_message = "Each permission set must attach its own AWS managed policy."
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this["AdministratorAccess"].session_duration == "PT4H"
    error_message = "The administrator session must stay at four hours."
  }
}

run "every_account_gets_both_sets_for_the_user_only" {
  command = apply

  assert {
    condition = join(",", output.assignment_keys) == join(",", [
      "AdministratorAccess/security", "AdministratorAccess/workforce",
      "ReadOnlyAccess/security", "ReadOnlyAccess/workforce",
    ])
    error_message = "The maintainer must be assigned both sets on every listed account."
  }

  assert {
    condition = alltrue([
      for a in aws_ssoadmin_account_assignment.maintainer :
      a.principal_type == "USER" && a.target_type == "AWS_ACCOUNT" && a.principal_id == "11111111-2222-3333-4444-555555555555"
    ])
    error_message = "Assignments must target the maintainer user and an account, never a group."
  }
}

run "assignment_to_an_unknown_set_is_rejected" {
  command = plan

  variables {
    assignments = { Missing = ["security"] }
  }

  expect_failures = [var.assignments]
}

run "assignment_to_an_unlisted_account_is_rejected" {
  command = plan

  variables {
    assignments = { AdministratorAccess = ["management"] }
  }

  expect_failures = [var.assignments]
}

run "only_aws_managed_policies_are_accepted" {
  command = plan

  variables {
    permission_sets = {
      Custom = {
        description        = "x"
        managed_policy_arn = "arn:aws:iam::111111111111:policy/Custom"
        session_duration   = "PT1H"
      }
    }
    assignments = {}
  }

  expect_failures = [var.permission_sets]
}
