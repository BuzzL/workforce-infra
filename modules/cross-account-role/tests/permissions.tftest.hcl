mock_provider "aws" {}

variables {
  name        = "qual-foundation-agent-role"
  description = "Read only agent."
  trust = {
    mode = "assume_role"
    assume_role = {
      principal_arn     = "arn:aws:iam::111122223333:role/wrkf-foundation-agent-task-role"
      source_account_id = "111122223333"
      external_ids      = ["0123456789abcdef-current"]
    }
  }
}

run "permission_set_is_rendered_literally" {
  command = apply

  variables {
    statements = [
      {
        sid       = "ReadFunctions"
        actions   = ["lambda:GetFunctionConfiguration", "lambda:GetAlias"]
        resources = ["arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function"]
      },
      {
        sid                 = "DescribeLogGroups"
        actions             = ["logs:DescribeLogGroups"]
        resources           = ["*"]
        any_resource_reason = "logs:DescribeLogGroups has no resource type"
      },
      {
        sid       = "TemplateSummary"
        actions   = ["cloudformation:GetTemplateSummary"]
        resources = ["*"]
        conditions = {
          StringLike = { "cloudformation:TemplateUrl" = ["https://artifacts.example/testbed/*"] }
        }
        any_resource_reason = "no stack exists yet to name"
      },
    ]
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.permissions[0].policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ReadFunctions"
          Effect   = "Allow"
          Action   = ["lambda:GetFunctionConfiguration", "lambda:GetAlias"]
          Resource = ["arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function"]
        },
        {
          Sid      = "DescribeLogGroups"
          Effect   = "Allow"
          Action   = ["logs:DescribeLogGroups"]
          Resource = ["*"]
        },
        {
          Sid      = "TemplateSummary"
          Effect   = "Allow"
          Action   = ["cloudformation:GetTemplateSummary"]
          Resource = ["*"]
          Condition = {
            StringLike = { "cloudformation:TemplateUrl" = ["https://artifacts.example/testbed/*"] }
          }
        },
      ]
    }
    error_message = "The permission set must be rendered exactly as given."
  }

  assert {
    condition     = tostring(jsonencode(aws_iam_role_policies_exclusive.this.policy_names)) == "[\"permissions\"]" && jsonencode(aws_iam_role_policy_attachments_exclusive.this.policy_arns) == "[]"
    error_message = "The module must own the role's permissions completely: one inline policy, no managed attachment."
  }
}

# The rendered documents never use the negated forms, whatever the input.
run "no_negated_forms_and_no_star_principal" {
  command = apply

  variables {
    statements = [{
      sid       = "ReadStacks"
      actions   = ["cloudformation:DescribeStacks"]
      resources = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/qual-foundation-testbed-*-stack/*"]
    }]
  }

  assert {
    condition = alltrue([
      for doc in [aws_iam_role.this.assume_role_policy, aws_iam_role_policy.permissions[0].policy] :
      !strcontains(doc, "NotAction") && !strcontains(doc, "NotPrincipal") && !strcontains(doc, "NotResource")
    ])
    error_message = "No document may use NotAction, NotPrincipal or NotResource."
  }

  assert {
    condition     = !can(regex("\"(AWS|Federated|Service)\":\"\\*\"", aws_iam_role.this.assume_role_policy))
    error_message = "The trust policy must not have a * principal."
  }

  assert {
    condition     = !can(regex("\"Action\":\"?\\[?\"\\*\"|:\\*\"", aws_iam_role_policy.permissions[0].policy))
    error_message = "The permission policy must not have a * or service:* action."
  }
}

run "no_statements_no_inline_policy" {
  command = apply

  assert {
    condition     = length(aws_iam_role_policy.permissions) == 0 && jsonencode(aws_iam_role_policies_exclusive.this.policy_names) == "[]"
    error_message = "A role without statements has no inline policy and owns an empty set."
  }
}

run "boundary_is_attached_when_given" {
  command = apply

  variables {
    permissions_boundary_arn = "arn:aws:iam::111122223333:policy/platform/qual-foundation-testbed-boundary"
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::111122223333:policy/platform/qual-foundation-testbed-boundary"
    error_message = "The boundary must be attached to the role."
  }
}

run "refuses_star_action" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["*"], resources = ["arn:aws:s3:::b"] }]
  }
}

run "refuses_service_star_action" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["s3:*"], resources = ["arn:aws:s3:::b"] }]
  }
}

run "refuses_prefix_wildcard_action_in_allow" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["s3:Get*"], resources = ["arn:aws:s3:::b"] }]
  }
}

run "refuses_star_resource_without_reason" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["logs:DescribeLogGroups"], resources = ["*"] }]
  }
}

run "refuses_unknown_effect" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", effect = "NotAllow", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::b/*"] }]
  }
}

run "refuses_wildcard_deny_without_condition" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", effect = "Deny", actions = ["s3:*"], resources = ["arn:aws:s3:::b/*"] }]
  }
}

run "refuses_deny_everything_on_star_resource" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", effect = "Deny", actions = ["s3:GetObject"], resources = ["*"] }]
  }
}

# A narrowed Deny is the one allowed wildcard, and is asserted literally.
run "narrowed_deny_wildcard_is_rendered_literally" {
  command = apply

  variables {
    statements = [{
      sid       = "TlsOnly"
      effect    = "Deny"
      actions   = ["s3:*"]
      resources = ["arn:aws:s3:::bucket", "arn:aws:s3:::bucket/*"]
      conditions = {
        Bool = { "aws:SecureTransport" = ["false"] }
      }
    }]
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.permissions[0].policy).Statement == [{
      Sid       = "TlsOnly"
      Effect    = "Deny"
      Action    = ["s3:*"]
      Resource  = ["arn:aws:s3:::bucket", "arn:aws:s3:::bucket/*"]
      Condition = { Bool = { "aws:SecureTransport" = ["false"] } }
    }]
    error_message = "A narrowed Deny must be rendered with its condition."
  }
}

run "refuses_wildcard_service_or_account_in_allow_resource" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["iam:PassRole"], resources = ["arn:aws:iam::*:role/*"] }]
  }
}

run "refuses_wildcard_start_of_resource_part" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::*"] }]
  }
}

run "refuses_blank_any_resource_reason" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["logs:DescribeLogGroups"], resources = ["*"], any_resource_reason = "  " }]
  }
}

run "refuses_empty_condition_as_narrowing" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", effect = "Deny", actions = ["s3:*"], resources = ["*"], conditions = { StringEquals = {} } }]
  }
}

run "refuses_condition_key_without_value" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [{ sid = "X", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::b/*"], conditions = { StringEquals = { "aws:SourceVpc" = [] } } }]
  }
}

run "refuses_duplicate_sid" {
  command         = plan
  expect_failures = [var.statements]

  variables {
    statements = [
      { sid = "X", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::b/*"] },
      { sid = "X", actions = ["s3:ListBucket"], resources = ["arn:aws:s3:::b"] },
    ]
  }
}
