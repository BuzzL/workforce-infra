# Literal assertions on purpose: a change to the permission set must show up as a diff here.
mock_provider "aws" {}

variables {
  region               = "eu-west-1"
  account_id           = "111122223333"
  principal_arn        = "arn:aws:iam::444455556666:role/wrkf-foundation-agent-task-role"
  workforce_account_id = "444455556666"
  external_ids         = ["0123456789abcdef-current"]
}

run "test_permission_set" {
  command = apply

  variables {
    key = "test"
  }

  assert {
    condition     = output.name == "test-foundation-agent-role"
    error_message = "The role must be named <key>-foundation-agent-role."
  }

  assert {
    condition = jsondecode(output.permissions_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ReadFunctions"
          Effect   = "Allow"
          Action   = ["lambda:GetFunctionConfiguration", "lambda:GetAlias", "lambda:ListVersionsByFunction", "lambda:ListAliases"]
          Resource = ["arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function", "arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function:*"]
        },
        {
          Sid      = "ReadStacks"
          Effect   = "Allow"
          Action   = ["cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*"]
        },
        {
          Sid      = "ReadLogGroups"
          Effect   = "Allow"
          Action   = ["logs:FilterLogEvents", "logs:DescribeLogStreams"]
          Resource = ["arn:aws:logs:eu-west-1:111122223333:log-group:/aws/lambda/test-foundation-testbed-*-function", "arn:aws:logs:eu-west-1:111122223333:log-group:/aws/lambda/test-foundation-testbed-*-function:*"]
        },
        {
          Sid      = "ReadLogStreams"
          Effect   = "Allow"
          Action   = ["logs:GetLogEvents"]
          Resource = ["arn:aws:logs:eu-west-1:111122223333:log-group:/aws/lambda/test-foundation-testbed-*-function:log-stream:*"]
        },
        {
          Sid      = "ReadAlarms"
          Effect   = "Allow"
          Action   = ["cloudwatch:DescribeAlarms"]
          Resource = ["arn:aws:cloudwatch:eu-west-1:111122223333:alarm:test-foundation-testbed-*-alarm"]
        },
      ]
    }
    error_message = "The agent permission set must be exactly the read only table of docs/ENVIRONMENT_PERMISSIONS.md."
  }
}

run "trust_names_the_agent_task_role_only" {
  command = apply

  variables {
    key = "qual"
  }

  assert {
    condition = jsondecode(output.trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::444455556666:role/wrkf-foundation-agent-task-role" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = "444455556666"
            "sts:ExternalId"       = ["0123456789abcdef-current"]
          }
          ArnEquals  = { "aws:PrincipalArn" = "arn:aws:iam::444455556666:role/wrkf-foundation-agent-task-role" }
          StringLike = { "sts:RoleSessionName" = "agent-*" }
        }
      }]
    }
    error_message = "Only the agent task role of workforce may assume the role, with the ExternalId and an agent-* session name."
  }
}

run "trust_adds_the_matrix_runner_role_when_given" {
  command = apply

  variables {
    key                  = "qual"
    extra_principal_arns = ["arn:aws:iam::444455556666:role/platform/wrkf-foundation-matrix-quality-role"]
  }

  assert {
    condition = jsondecode(output.trust_policy).Statement[0].Principal == {
      AWS = [
        "arn:aws:iam::444455556666:role/wrkf-foundation-agent-task-role",
        "arn:aws:iam::444455556666:role/platform/wrkf-foundation-matrix-quality-role",
      ]
    }
    error_message = "The agent task role and the matrix runner role of the environment, and nobody else, may assume the role."
  }

  assert {
    condition     = jsondecode(output.trust_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == ["0123456789abcdef-current"] && jsondecode(output.trust_policy).Statement[0].Condition.StringLike["sts:RoleSessionName"] == "agent-*"
    error_message = "The runner is held to the same ExternalId and session name as the agent task role."
  }
}

run "refuses_an_extra_principal_outside_workforce" {
  command         = plan
  expect_failures = [var.extra_principal_arns]

  variables {
    key                  = "qual"
    extra_principal_arns = ["arn:aws:iam::111122223333:role/platform/test-foundation-agent-role"]
  }
}

# Narrowing rule of docs/ENVIRONMENT_PERMISSIONS.md: allowed(demo) ⊆ allowed(quality) ⊆ allowed(test),
# as the set of (action, resource) pairs once the account key is taken out of the names. The agent
# role is identical everywhere, so both inclusions hold with equality.
run "quality_role" {
  command = apply

  variables {
    key = "qual"
  }
}

run "demo_role" {
  command = apply

  variables {
    key = "demo"
  }
}

run "narrowing_demo_in_quality_in_test" {
  command = apply

  variables {
    key = "test"
  }

  assert {
    condition     = alltrue([for p in distinct(flatten([for s in jsondecode(run.demo_role.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${replace(r, "demo-foundation", "KEY-foundation")}"]]])) : contains(distinct(flatten([for s in jsondecode(run.quality_role.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${replace(r, "qual-foundation", "KEY-foundation")}"]]])), p)]) && alltrue([for p in distinct(flatten([for s in jsondecode(run.quality_role.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${replace(r, "qual-foundation", "KEY-foundation")}"]]])) : contains(distinct(flatten([for s in jsondecode(output.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${replace(r, "test-foundation", "KEY-foundation")}"]]])), p)])
    error_message = "allowed(demo) must be included in allowed(quality), which must be included in allowed(test)."
  }

  assert {
    condition     = length(distinct(flatten([for s in jsondecode(run.demo_role.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${replace(r, "demo-foundation", "KEY-foundation")}"]]]))) == 16 && length(distinct(flatten([for s in jsondecode(run.quality_role.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${replace(r, "qual-foundation", "KEY-foundation")}"]]]))) == 16 && length(distinct(flatten([for s in jsondecode(output.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${replace(r, "test-foundation", "KEY-foundation")}"]]]))) == 16
    error_message = "The agent role is identical in the three environments: 16 action and resource pairs each."
  }

  assert {
    condition     = alltrue([for s in jsondecode(run.demo_role.permissions_policy).Statement : alltrue([for r in s.Resource : strcontains(r, "demo-foundation")])]) && alltrue([for s in jsondecode(run.quality_role.permissions_policy).Statement : alltrue([for r in s.Resource : strcontains(r, "qual-foundation")])])
    error_message = "Every resource must belong to the names of its own account."
  }
}

run "no_write_and_no_escalation" {
  command = apply

  variables {
    key = "test"
  }

  assert {
    condition = alltrue([for s in jsondecode(output.permissions_policy).Statement : s.Effect == "Allow" && alltrue([
      for a in s.Action : can(regex("^(lambda:(Get|List)|cloudformation:Describe|logs:(Filter|Describe|Get)|cloudwatch:Describe)", a))
    ])])
    error_message = "The agent role holds read actions only."
  }

  assert {
    condition = !anytrue([for s in jsondecode(output.permissions_policy).Statement : anytrue([
      for a in s.Action : contains(["lambda:GetFunction", "cloudformation:GetTemplate"], a) || startswith(a, "iam:") || startswith(a, "sts:")
    ])])
    error_message = "GetFunction (code download URL), GetTemplate, iam and sts are out."
  }

  assert {
    condition     = !anytrue([for s in jsondecode(output.permissions_policy).Statement : contains(s.Resource, "*")])
    error_message = "No resource may be a bare wildcard."
  }
}

run "refuses_a_key_that_is_not_an_environment" {
  command = plan

  variables {
    key = "wrkf"
  }

  expect_failures = [var.key]
}

run "refuses_a_reserved_application_name" {
  command = plan

  variables {
    key          = "test"
    applications = ["agent"]
  }

  expect_failures = [var.applications]
}

run "refuses_a_principal_that_is_not_a_role" {
  command = plan

  variables {
    key           = "test"
    principal_arn = "arn:aws:iam::444455556666:root"
  }

  expect_failures = [var.principal_arn]
}
