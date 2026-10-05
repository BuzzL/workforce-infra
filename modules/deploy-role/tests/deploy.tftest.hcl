# Literal assertions on purpose: a change to the permission set must show up as a diff here.
mock_provider "aws" {}

variables {
  region               = "eu-west-1"
  account_id           = "111122223333"
  oidc_provider_arn    = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
  github_owner         = "BuzzL"
  github_owner_id      = "6116516"
  github_repository    = "workforce-testbed"
  github_repository_id = "1394609283"
  artifact_bucket      = "example-artifacts"
  artifact_prefix      = "testbed"
  stacks               = ["main"]
}

run "test_permission_set" {
  command = apply

  variables {
    key = "test"
  }

  assert {
    condition     = output.name == "test-foundation-testbed-deploy-role"
    error_message = "The role must be named <key>-foundation-<app>-deploy-role."
  }

  assert {
    condition = jsondecode(output.permissions_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "CreateStacks"
          Effect   = "Allow"
          Action   = ["cloudformation:CreateStack"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*"]
          Condition = {
            StringEquals = {
              "cloudformation:RoleArn"     = ["arn:aws:iam::111122223333:role/platform/test-foundation-testbed-exec-role"]
              "aws:RequestTag/App"         = ["testbed"]
              "aws:RequestTag/Environment" = ["test"]
            }
            StringLike = { "cloudformation:TemplateUrl" = ["https://example-artifacts.s3.eu-west-1.amazonaws.com/testbed/*"] }
          }
        },
        {
          Sid       = "DeleteStacks"
          Effect    = "Allow"
          Action    = ["cloudformation:DeleteStack"]
          Resource  = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*"]
          Condition = { StringEquals = { "cloudformation:RoleArn" = ["arn:aws:iam::111122223333:role/platform/test-foundation-testbed-exec-role"] } }
        },
        {
          Sid      = "CreateChangeSets"
          Effect   = "Allow"
          Action   = ["cloudformation:CreateChangeSet"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*"]
          Condition = {
            StringEquals = {
              "cloudformation:RoleArn"     = ["arn:aws:iam::111122223333:role/platform/test-foundation-testbed-exec-role"]
              "aws:RequestTag/App"         = ["testbed"]
              "aws:RequestTag/Environment" = ["test"]
            }
            StringLike = { "cloudformation:TemplateUrl" = ["https://example-artifacts.s3.eu-west-1.amazonaws.com/testbed/*"] }
          }
        },
        {
          Sid      = "FollowChangeSets"
          Effect   = "Allow"
          Action   = ["cloudformation:ExecuteChangeSet", "cloudformation:DeleteChangeSet", "cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents", "cloudformation:DescribeChangeSet", "cloudformation:GetTemplate"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*"]
        },
        {
          Sid       = "ReadTemplateSummary"
          Effect    = "Allow"
          Action    = ["cloudformation:GetTemplateSummary"]
          Resource  = ["*"]
          Condition = { StringLike = { "cloudformation:TemplateUrl" = ["https://example-artifacts.s3.eu-west-1.amazonaws.com/testbed/*"] } }
        },
        {
          Sid       = "TagStacks"
          Effect    = "Allow"
          Action    = ["cloudformation:TagResource", "cloudformation:UntagResource"]
          Resource  = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*"]
          Condition = { "ForAllValues:StringEquals" = { "aws:TagKeys" = ["App", "Archetype", "Environment", "ManagedBy", "Project", "Repository", "Stack", "Target"] } }
        },
        {
          Sid       = "PassExecutionRole"
          Effect    = "Allow"
          Action    = ["iam:PassRole"]
          Resource  = ["arn:aws:iam::111122223333:role/platform/test-foundation-testbed-exec-role"]
          Condition = { StringEquals = { "iam:PassedToService" = ["cloudformation.amazonaws.com"] } }
        },
        {
          Sid      = "ReadArtifact"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::example-artifacts/testbed/*"]
        },
        {
          Sid      = "CheckFunctions"
          Effect   = "Allow"
          Action   = ["lambda:GetFunctionConfiguration", "lambda:GetAlias"]
          Resource = ["arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function", "arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function:*"]
        },
        {
          Sid      = "CheckAlarms"
          Effect   = "Allow"
          Action   = ["cloudwatch:DescribeAlarms"]
          Resource = ["arn:aws:cloudwatch:eu-west-1:111122223333:alarm:test-foundation-testbed-*-alarm"]
        },
      ]
    }
    error_message = "The test deploy permission set must be exactly the deploy table of docs/ENVIRONMENT_PERMISSIONS.md."
  }
}

run "quality_permission_set" {
  command = apply

  variables {
    key = "qual"
  }

  assert {
    condition     = output.name == "qual-foundation-testbed-deploy-role"
    error_message = "The role must be named <key>-foundation-<app>-deploy-role."
  }

  assert {
    condition = jsondecode(output.permissions_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "CreateChangeSets"
          Effect   = "Allow"
          Action   = ["cloudformation:CreateChangeSet"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/qual-foundation-testbed-main-stack/*"]
          Condition = {
            StringEquals = {
              "cloudformation:RoleArn"     = ["arn:aws:iam::111122223333:role/platform/qual-foundation-testbed-exec-role"]
              "aws:RequestTag/App"         = ["testbed"]
              "aws:RequestTag/Environment" = ["quality"]
            }
            StringLike = { "cloudformation:TemplateUrl" = ["https://example-artifacts.s3.eu-west-1.amazonaws.com/testbed/*"] }
          }
        },
        {
          Sid      = "FollowChangeSets"
          Effect   = "Allow"
          Action   = ["cloudformation:ExecuteChangeSet", "cloudformation:DeleteChangeSet", "cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents", "cloudformation:DescribeChangeSet", "cloudformation:GetTemplate"]
          Resource = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/qual-foundation-testbed-main-stack/*"]
        },
        {
          Sid       = "ReadTemplateSummary"
          Effect    = "Allow"
          Action    = ["cloudformation:GetTemplateSummary"]
          Resource  = ["*"]
          Condition = { StringLike = { "cloudformation:TemplateUrl" = ["https://example-artifacts.s3.eu-west-1.amazonaws.com/testbed/*"] } }
        },
        {
          Sid       = "TagStacks"
          Effect    = "Allow"
          Action    = ["cloudformation:TagResource", "cloudformation:UntagResource"]
          Resource  = ["arn:aws:cloudformation:eu-west-1:111122223333:stack/qual-foundation-testbed-main-stack/*"]
          Condition = { "ForAllValues:StringEquals" = { "aws:TagKeys" = ["App", "Archetype", "Environment", "ManagedBy", "Project", "Repository", "Stack", "Target"] } }
        },
        {
          Sid       = "PassExecutionRole"
          Effect    = "Allow"
          Action    = ["iam:PassRole"]
          Resource  = ["arn:aws:iam::111122223333:role/platform/qual-foundation-testbed-exec-role"]
          Condition = { StringEquals = { "iam:PassedToService" = ["cloudformation.amazonaws.com"] } }
        },
        {
          Sid      = "ReadArtifact"
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::example-artifacts/testbed/*"]
        },
        {
          Sid      = "CheckFunctions"
          Effect   = "Allow"
          Action   = ["lambda:GetFunctionConfiguration", "lambda:GetAlias"]
          Resource = ["arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function", "arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function:*"]
        },
        {
          Sid      = "CheckAlarms"
          Effect   = "Allow"
          Action   = ["cloudwatch:DescribeAlarms"]
          Resource = ["arn:aws:cloudwatch:eu-west-1:111122223333:alarm:qual-foundation-testbed-*-alarm"]
        },
      ]
    }
    error_message = "The quality deploy permission set must be the deploy table: no stack creation or deletion, and only the registered stacks."
  }
}

run "demo_permission_set" {
  command = apply

  variables {
    key = "demo"
  }

  assert {
    condition     = output.name == "demo-foundation-testbed-deploy-role"
    error_message = "The role must be named <key>-foundation-<app>-deploy-role."
  }

  # Equal to quality but for the names: what narrows demo is its trust (the reviewer) and its execution role.
  assert {
    condition     = replace(replace(output.permissions_policy, "demo-foundation", "KEY-foundation"), "\"demo\"", "\"quality\"") == replace(run.quality_permission_set.permissions_policy, "qual-foundation", "KEY-foundation")
    error_message = "The demo deploy permission set must equal the quality one, key and environment name aside."
  }

  assert {
    condition     = length(regexall("CreateStack|DeleteStack", output.permissions_policy)) == 0
    error_message = "demo cannot create or delete a stack."
  }
}

run "trust_is_one_exact_subject_per_environment" {
  command = apply

  variables {
    key = "demo"
  }

  assert {
    condition = jsondecode(output.trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-testbed@1394609283:environment:demo"
          }
        }
      }]
    }
    error_message = "Only the application's repository in the demo GitHub Environment may assume the role, by exact subject."
  }
}

run "quality_trust_names_the_quality_environment_not_the_key" {
  command = apply

  variables {
    key = "qual"
  }

  assert {
    condition     = strcontains(output.trust_policy, "workforce-testbed@1394609283:environment:quality\"") && !strcontains(output.trust_policy, "environment:qual\"")
    error_message = "The subject carries the environment name (quality), never the key (qual)."
  }
}

# The inclusion compares (action, resource) pairs only. The conditions of each statement are pinned
# by the literal permission-set runs above, which is what stops a dropped condition.
# Narrowing rule of docs/ENVIRONMENT_PERMISSIONS.md: allowed(demo) ⊆ allowed(quality) ⊆ allowed(test),
# as (action, resource pattern) pairs once the account key is taken out of the names. A resource of
# a narrower role is included when a pattern of the wider one matches it (a registered stack is
# matched by the test pattern for any stack).
run "agent_role_test" {
  command = apply

  module {
    source = "../agent-role"
  }

  variables {
    key                  = "test"
    principal_arn        = "arn:aws:iam::444455556666:role/wrkf-foundation-agent-task-role"
    workforce_account_id = "444455556666"
    external_ids         = ["0123456789abcdef-current"]
  }
}

run "agent_role_quality" {
  command = apply

  module {
    source = "../agent-role"
  }

  variables {
    key                  = "qual"
    principal_arn        = "arn:aws:iam::444455556666:role/wrkf-foundation-agent-task-role"
    workforce_account_id = "444455556666"
    external_ids         = ["0123456789abcdef-current"]
  }
}

run "narrowing_demo_in_quality_in_test" {
  command = apply

  variables {
    key = "test"
  }

  assert {
    condition = alltrue([
      for p in flatten([for s in jsondecode(run.demo_permission_set.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : { a = a, r = replace(r, "demo-foundation", "KEY-foundation") }]]]) :
      anytrue([for q in flatten([for s in jsondecode(run.quality_permission_set.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : { a = a, r = replace(r, "qual-foundation", "KEY-foundation") }]]]) : q.a == p.a && can(regex("^${replace(q.r, "*", ".*")}$", p.r))])
    ])
    error_message = "allowed(demo) must be included in allowed(quality)."
  }

  assert {
    condition = alltrue([
      for p in flatten([for s in jsondecode(run.quality_permission_set.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : { a = a, r = replace(r, "qual-foundation", "KEY-foundation") }]]]) :
      anytrue([for q in flatten([for s in jsondecode(output.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : { a = a, r = replace(r, "test-foundation", "KEY-foundation") }]]]) : q.a == p.a && can(regex("^${replace(q.r, "*", ".*")}$", p.r))])
    ])
    error_message = "allowed(quality) must be included in allowed(test)."
  }

  # The inclusion is strict from test to quality: test can create and delete stacks and quality cannot.
  assert {
    condition = anytrue([
      for p in flatten([for s in jsondecode(output.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : { a = a, r = replace(r, "test-foundation", "KEY-foundation") }]]]) :
      !anytrue([for q in flatten([for s in jsondecode(run.quality_permission_set.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : { a = a, r = replace(r, "qual-foundation", "KEY-foundation") }]]]) : q.a == p.a && can(regex("^${replace(q.r, "*", ".*")}$", p.r))])
    ])
    error_message = "allowed(test) must hold something quality does not: the narrowing from test to quality is strict."
  }
}

# The deploy and agent roles share only what the matrix gives both, the post-deploy reads, and
# nothing of the agent's log, list or version reads.
run "overlap_with_the_agent_role_is_the_matrix_reads_only" {
  command = apply

  variables {
    key = "test"
  }

  assert {
    condition = toset(distinct([
      for p in flatten([for s in jsondecode(output.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${r}"]]]) : p
      if contains(flatten([for s in jsondecode(run.agent_role_test.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${r}"]]]), p)
      ])) == toset([
      "lambda:GetFunctionConfiguration arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function",
      "lambda:GetFunctionConfiguration arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function:*",
      "lambda:GetAlias arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function",
      "lambda:GetAlias arn:aws:lambda:eu-west-1:111122223333:function:test-foundation-testbed-*-function:*",
      "cloudformation:DescribeStacks arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*",
      "cloudformation:DescribeStackEvents arn:aws:cloudformation:eu-west-1:111122223333:stack/test-foundation-testbed-*-stack/*",
      "cloudwatch:DescribeAlarms arn:aws:cloudwatch:eu-west-1:111122223333:alarm:test-foundation-testbed-*-alarm",
    ])
    error_message = "In test the deploy and agent roles may overlap only on the function, stack and alarm reads of the matrix."
  }
}

run "overlap_with_the_agent_role_in_quality_is_function_and_alarm_reads_only" {
  command = apply

  variables {
    key = "qual"
  }

  # The deploy role names the registered stacks, the agent role the pattern: no identical stack resource.
  assert {
    condition = toset(distinct([
      for p in flatten([for s in jsondecode(output.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${r}"]]]) : p
      if contains(flatten([for s in jsondecode(run.agent_role_quality.permissions_policy).Statement : [for a in s.Action : [for r in s.Resource : "${a} ${r}"]]]), p)
      ])) == toset([
      "lambda:GetFunctionConfiguration arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function",
      "lambda:GetFunctionConfiguration arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function:*",
      "lambda:GetAlias arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function",
      "lambda:GetAlias arn:aws:lambda:eu-west-1:111122223333:function:qual-foundation-testbed-*-function:*",
      "cloudwatch:DescribeAlarms arn:aws:cloudwatch:eu-west-1:111122223333:alarm:qual-foundation-testbed-*-alarm",
    ])
    error_message = "In quality the deploy and agent roles may overlap only on the function and alarm reads of the matrix."
  }
}

run "no_escalation" {
  command = apply

  variables {
    key = "test"
  }

  # iam is one PassRole on one role, and nothing assumes a role or touches the organization.
  assert {
    condition = alltrue([for s in jsondecode(output.permissions_policy).Statement : s.Effect == "Allow" && alltrue([
      for a in s.Action : !startswith(a, "iam:") || (a == "iam:PassRole" && s.Resource == ["arn:aws:iam::111122223333:role/platform/test-foundation-testbed-exec-role"])
    ])])
    error_message = "The only iam action is PassRole of the execution role."
  }

  assert {
    condition = !anytrue([for s in jsondecode(output.permissions_policy).Statement : anytrue([
      for a in s.Action : startswith(a, "sts:") || startswith(a, "organizations:") || startswith(a, "account:") || a == "cloudformation:UpdateStack" || startswith(a, "lambda:Update") || startswith(a, "lambda:Create") || startswith(a, "lambda:Delete")
    ])])
    error_message = "No role chaining, no organization access, no UpdateStack, no direct Lambda write."
  }

  # The one bare resource is GetTemplateSummary, narrowed to the artifact prefix.
  assert {
    condition = [for s in jsondecode(output.permissions_policy).Statement : s.Sid if contains(s.Resource, "*")] == ["ReadTemplateSummary"] && alltrue([
      for s in jsondecode(output.permissions_policy).Statement : s.Action == ["cloudformation:GetTemplateSummary"] if contains(s.Resource, "*")
    ])
    error_message = "Only GetTemplateSummary may use resource *, and only through a TemplateUrl condition."
  }

  # Every action that can create a stack or pass the role goes through the execution role.
  assert {
    condition = alltrue([for s in jsondecode(output.permissions_policy).Statement : try(s.Condition.StringEquals["cloudformation:RoleArn"] == ["arn:aws:iam::111122223333:role/platform/test-foundation-testbed-exec-role"], false)
    if anytrue([for a in s.Action : contains(["cloudformation:CreateStack", "cloudformation:CreateChangeSet", "cloudformation:DeleteStack"], a)])])
    error_message = "CreateStack, CreateChangeSet and DeleteStack must name the execution role."
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
    key         = "test"
    application = "platform"
  }

  expect_failures = [var.application]
}

run "refuses_no_registered_stack" {
  command = plan

  variables {
    key    = "qual"
    stacks = []
  }

  expect_failures = [var.stacks]
}

run "refuses_a_wildcard_stack_qualifier" {
  command = plan

  variables {
    key    = "qual"
    stacks = ["*"]
  }

  expect_failures = [var.stacks]
}

run "refuses_a_provider_that_is_not_github" {
  command = plan

  variables {
    key               = "test"
    oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/example.com"
  }

  expect_failures = [var.oidc_provider_arn]
}

run "refuses_a_wildcard_in_the_artifact_prefix" {
  command = plan

  variables {
    key             = "test"
    artifact_prefix = "testbed/*"
  }

  expect_failures = [var.artifact_prefix]
}

run "refuses_a_repository_that_widens_the_subject" {
  command = plan

  variables {
    key               = "test"
    github_repository = "workforce-*"
  }

  expect_failures = [var.github_repository]
}
