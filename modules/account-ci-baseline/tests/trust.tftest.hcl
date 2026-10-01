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
