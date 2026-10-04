# Literal assertions on purpose: a change to the trust must show up as a diff here.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

variables {
  account_name      = "security"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
  state_key         = "live/accounts/security/terraform.tfstate"
}

run "provider" {
  command = apply

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com" && aws_iam_openid_connect_provider.github.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "The provider must be GitHub's, with the sts.amazonaws.com audience only."
  }
}

run "apply_role_trust" {
  command = apply

  assert {
    condition     = aws_iam_role.apply.name == "github-infra-security"
    error_message = "Unexpected apply role name."
  }

  assert {
    condition = jsondecode(aws_iam_role.apply.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-infra@1394667495:environment:security"
          }
        }
      }]
    }
    error_message = "The apply role must trust exactly one repository and the security environment, with StringEquals on aud and sub."
  }
}

run "plan_role_trust" {
  command = apply

  assert {
    condition = jsondecode(aws_iam_role.plan.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-infra@1394667495:environment:security-plan"
          }
        }
      }]
    }
    error_message = "The plan role must trust exactly one repository and the security-plan environment."
  }
}

run "environment_naming_and_path" {
  command = apply

  variables {
    account_name    = "quality"
    apply_role_name = "qual-foundation-infra-role"
    plan_role_name  = "qual-foundation-infra-plan-role"
    role_path       = "/platform/"
  }

  assert {
    condition     = aws_iam_role.apply.name == "qual-foundation-infra-role" && aws_iam_role.plan.name == "qual-foundation-infra-plan-role"
    error_message = "The roles must carry the names of docs/ENVIRONMENT_PERMISSIONS.md."
  }

  assert {
    condition     = aws_iam_role.apply.path == "/platform/" && aws_iam_role.plan.path == "/platform/"
    error_message = "Both roles must live under /platform/."
  }

  # The trust follows the account name (the GitHub Environment), not the role name.
  assert {
    condition = (
      jsondecode(aws_iam_role.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:BuzzL@6116516/workforce-infra@1394667495:environment:quality"
      && jsondecode(aws_iam_role.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:BuzzL@6116516/workforce-infra@1394667495:environment:quality-plan"
    )
    error_message = "The subjects must stay the exact environment names quality and quality-plan."
  }

  # A role under a path is read through its ARN with the path in it.
  assert {
    condition = contains(flatten([
      for s in jsondecode(aws_iam_role_policy.apply_baseline_read.policy).Statement : s.Resource if s.Sid == "ReadBaselineRoles"
    ]), "arn:aws:iam::111122223333:role/platform/qual-foundation-infra-role")
    error_message = "The baseline read must name the roles with their path."
  }
}

run "legacy_names_are_unchanged" {
  command = apply

  assert {
    condition     = aws_iam_role.apply.name == "github-infra-security" && aws_iam_role.apply.path == "/"
    error_message = "Without the new inputs the roles keep their legacy name and path."
  }
}

run "environment_names_are_strict" {
  command = plan

  variables {
    account_name    = "quality"
    apply_role_name = "quality-foundation-infra-role"
  }

  expect_failures = [var.apply_role_name]
}

run "plan_role_name_is_strict" {
  command = plan

  variables {
    account_name   = "test"
    plan_role_name = "test-foundation-agent-role"
  }

  expect_failures = [var.plan_role_name]
}

run "role_path_is_strict" {
  command = plan

  variables {
    role_path = "/other/"
  }

  expect_failures = [var.role_path]
}
