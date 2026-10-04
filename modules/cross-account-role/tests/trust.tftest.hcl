# Literal assertions on purpose: a change to the trust must show up as a diff here.
mock_provider "aws" {}

variables {
  name        = "qual-foundation-agent-role"
  description = "Assumed by the developer agent."
}

run "assume_role_trust" {
  command = apply

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn        = "arn:aws:iam::111122223333:role/platform/wrkf-foundation-agent-task-role"
        source_account_id    = "111122223333"
        external_ids         = ["0123456789abcdef-current"]
        session_name_pattern = "agent-*"
      }
    }
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::111122223333:role/platform/wrkf-foundation-agent-task-role" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = "111122223333"
            "sts:ExternalId"       = ["0123456789abcdef-current"]
          }
          ArnEquals  = { "aws:PrincipalArn" = "arn:aws:iam::111122223333:role/platform/wrkf-foundation-agent-task-role" }
          StringLike = { "sts:RoleSessionName" = "agent-*" }
        }
      }]
    }
    error_message = "AssumeRole trust must name one role and require the source account, the principal ARN, the ExternalId and the session name pattern."
  }

  assert {
    condition     = aws_iam_role.this.path == "/platform/" && aws_iam_role.this.name == "qual-foundation-agent-role"
    error_message = "The role must live under /platform/ with the given name."
  }
}

run "assume_role_rotation_holds_two_external_ids" {
  command = apply

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::111122223333:role/wrkf-foundation-agent-task-role"
        source_account_id = "111122223333"
        external_ids      = ["0123456789abcdef-old", "0123456789abcdef-new"]
      }
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == ["0123456789abcdef-old", "0123456789abcdef-new"]
    error_message = "A rotation must accept exactly the two ExternalIds."
  }

  assert {
    condition     = !can(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringLike)
    error_message = "Without a session name pattern there is no StringLike condition."
  }
}

run "web_identity_trust" {
  command = apply

  variables {
    name = "test-foundation-testbed-deploy-role"
    trust = {
      mode = "web_identity"
      web_identity = {
        provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
        subject      = "repo:BuzzL@6116516/workforce-testbed@1:environment:test"
      }
    }
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-testbed@1:environment:test"
          }
        }
      }]
    }
    error_message = "Web identity trust must be StringEquals on audience and on one exact subject."
  }
}

run "service_trust" {
  command = apply

  variables {
    name = "qual-foundation-testbed-exec-role"
    trust = {
      mode = "service"
      service = {
        principal          = "cloudformation.amazonaws.com"
        source_account_id  = "111122223333"
        source_arn_pattern = "arn:aws:cloudformation:eu-west-1:111122223333:stack/qual-foundation-testbed-*-stack/*"
      }
    }
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "cloudformation.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = "111122223333" }
          ArnLike      = { "aws:SourceArn" = "arn:aws:cloudformation:eu-west-1:111122223333:stack/qual-foundation-testbed-*-stack/*" }
        }
      }]
    }
    error_message = "Service trust must be bound to the account and to the stacks of the application."
  }
}

# Refusals: every one of these must fail at plan time.
run "refuses_wildcard_principal" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::111122223333:role/*"
        source_account_id = "111122223333"
        external_ids      = ["0123456789abcdef-current"]
      }
    }
  }
}

run "refuses_account_root_principal" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::111122223333:root"
        source_account_id = "111122223333"
        external_ids      = ["0123456789abcdef-current"]
      }
    }
  }
}

run "refuses_principal_outside_source_account" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::999988887777:role/other"
        source_account_id = "111122223333"
        external_ids      = ["0123456789abcdef-current"]
      }
    }
  }
}

run "refuses_missing_external_id" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::111122223333:role/other"
        source_account_id = "111122223333"
        external_ids      = []
      }
    }
  }
}

run "refuses_wildcard_external_id" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::111122223333:role/other"
        source_account_id = "111122223333"
        external_ids      = ["0123456789abcdef*"]
      }
    }
  }
}

run "refuses_open_session_name_pattern" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn        = "arn:aws:iam::111122223333:role/other"
        source_account_id    = "111122223333"
        external_ids         = ["0123456789abcdef-current"]
        session_name_pattern = "*"
      }
    }
  }
}

run "refuses_wildcard_subject" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    name = "test-foundation-testbed-deploy-role"
    trust = {
      mode = "web_identity"
      web_identity = {
        provider_arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
        subject      = "repo:BuzzL@6116516/*"
      }
    }
  }
}

run "refuses_service_without_source_binding" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    name = "qual-foundation-testbed-exec-role"
    trust = {
      mode = "service"
      service = {
        principal          = "cloudformation.amazonaws.com"
        source_account_id  = "111122223333"
        source_arn_pattern = "arn:aws:cloudformation:eu-west-1:111122223333:*"
      }
    }
  }
}

run "refuses_two_trust_blocks" {
  command         = plan
  expect_failures = [var.trust]

  variables {
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::111122223333:role/other"
        source_account_id = "111122223333"
        external_ids      = ["0123456789abcdef-current"]
      }
      service = {
        principal          = "cloudformation.amazonaws.com"
        source_account_id  = "111122223333"
        source_arn_pattern = "arn:aws:cloudformation:eu-west-1:111122223333:stack/x/*"
      }
    }
  }
}

run "refuses_name_outside_the_convention" {
  command         = plan
  expect_failures = [var.name]

  variables {
    name = "github-infra-security"
    trust = {
      mode = "assume_role"
      assume_role = {
        principal_arn     = "arn:aws:iam::111122223333:role/other"
        source_account_id = "111122223333"
        external_ids      = ["0123456789abcdef-current"]
      }
    }
  }
}
