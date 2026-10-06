mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" }
  }
}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
}

run "wires_the_baseline" {
  command = apply

  # Its own key is the one CI derives from the stack path. The key of the stack that CI
  # applies is a different one: the apply role reaches that one and never this one.
  assert {
    condition     = local.state_key == "bootstrap/accounts/workforce/terraform.tfstate"
    error_message = "The state key must match the backend key CI derives from the stack path."
  }

  assert {
    condition     = local.live_state_key == "live/accounts/workforce/terraform.tfstate"
    error_message = "The apply role must reach the state of live/accounts/workforce."
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

# The agent roles of the environment accounts trust this role (docs/AGENT_ROLES.md).
run "agent_task_role_is_assumed_by_ecs_tasks_of_this_account_only" {
  command = apply

  assert {
    condition     = module.agent_role.name == "wrkf-foundation-agent-role"
    error_message = "The agent task role must be wrkf-foundation-agent-role."
  }

  assert {
    condition = jsondecode(module.agent_role.trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = { "aws:SourceAccount" = "111122223333" }
          ArnLike      = { "aws:SourceArn" = "arn:aws:ecs:eu-west-1:111122223333:task/*" }
        }
      }]
    }
    error_message = "Only ECS tasks of the workforce account may assume the agent task role."
  }

  # No permissions yet: each one arrives with the change that needs it.
  assert {
    condition     = module.agent_role.permissions_policy == null
    error_message = "The agent task role starts with no permissions."
  }

  assert {
    condition = jsonencode(local.agent_read_statements) == jsonencode([{
      Sid      = "ReadAgentTaskRole"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
      Resource = ["arn:aws:iam::111122223333:role/platform/wrkf-foundation-agent-role"]
    }])
    error_message = "The plan role may read exactly the agent task role and only through read actions."
  }

  # The statement really reaches the plan role: the stack passes it on to the baseline.
  assert {
    condition     = contains([for s in jsondecode(module.baseline.plan_read_policy).Statement : s.Sid], "ReadAgentTaskRole")
    error_message = "The plan role must be able to read the agent role."
  }
}

# The matrix runner roles (IAT-46): one per environment, one exact OIDC subject each, and the
# agent role of that environment is the only thing each may assume.
run "no_matrix_roles_while_the_variable_is_unset" {
  command = apply

  assert {
    condition     = length(module.matrix_role) == 0
    error_message = "Without var.matrix no matrix runner role exists."
  }
}

run "matrix_roles_trust_one_environment_each_and_assume_one_agent_role" {
  command = apply

  variables {
    matrix = {
      environment_account_ids = { test = "222233334444", quality = "333344445555", demo = "444455556666" }
    }
  }

  assert {
    condition     = [for env in ["test", "quality", "demo"] : module.matrix_role[env].name] == ["wrkf-foundation-matrix-test-role", "wrkf-foundation-matrix-quality-role", "wrkf-foundation-matrix-demo-role"]
    error_message = "The runner roles must be wrkf-foundation-matrix-<environment>-role."
  }

  assert {
    condition = jsondecode(module.matrix_role["quality"].trust_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com" }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:BuzzL@6116516/workforce-infra@1394667495:environment:quality-matrix"
          }
        }
      }]
    }
    error_message = "The quality runner role must be trusted for workforce-infra in the quality-matrix environment only."
  }

  assert {
    condition = jsondecode(module.matrix_role["demo"].permissions_policy) == {
      Version = "2012-10-17"
      Statement = [{
        Sid      = "AssumeTheAgentRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = ["arn:aws:iam::444455556666:role/platform/demo-foundation-agent-role"]
      }]
    }
    error_message = "The demo runner role may assume the agent role of the demo account and nothing else."
  }
}

run "matrix_needs_the_three_environments" {
  command         = plan
  expect_failures = [var.matrix]

  variables {
    matrix = {
      environment_account_ids = { test = "222233334444", quality = "333344445555" }
    }
  }
}
