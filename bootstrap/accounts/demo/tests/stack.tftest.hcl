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
    condition     = local.state_key == "bootstrap/accounts/demo/terraform.tfstate"
    error_message = "The state key must match the backend key CI derives from the stack path."
  }

  assert {
    condition     = local.live_state_key == "live/environments/demo/terraform.tfstate"
    error_message = "The apply role must reach the state of live/environments/demo."
  }

  assert {
    condition     = module.baseline.apply_role_arn != module.baseline.plan_role_arn
    error_message = "The apply and plan roles must be different roles."
  }
}

# Names and path of docs/ENVIRONMENT_PERMISSIONS.md, literally: a rename must show up here. The trust, one exact subject per environment, is asserted in modules/account-ci-baseline.
run "roles_follow_the_naming_rule" {
  command = apply

  assert {
    condition     = module.baseline.apply_role_name == "demo-foundation-infra-role" && module.baseline.plan_role_name == "demo-foundation-infra-plan-role" && module.baseline.role_path == "/platform/"
    error_message = "The roles must be demo-foundation-infra-role and demo-foundation-infra-plan-role under /platform/."
  }

}

run "bootstrap_account_id_must_be_12_digits" {
  command = plan

  variables {
    break_glass_account_id = "not-an-id"
  }

  expect_failures = [var.break_glass_account_id]
}

# The agent role is off until var.agent is set: no role and no extra read for the plan role.
run "no_agent_role_without_agent_variable" {
  command = apply

  assert {
    condition     = length(module.agent_role) == 0 && length(local.agent_read_statements) == 0
    error_message = "Without var.agent the stack creates no agent role and widens nothing."
  }
}

run "agent_role_named_by_key_and_read_by_the_plan_role_only" {
  command = apply

  variables {
    agent = {
      principal_arn        = "arn:aws:iam::444455556666:role/wrkf-foundation-agent-task-role"
      workforce_account_id = "444455556666"
      external_ids         = ["0123456789abcdef-current"]
    }
  }

  assert {
    condition     = module.agent_role[0].name == "demo-foundation-agent-role"
    error_message = "The agent role must be demo-foundation-agent-role."
  }

  # The plan role (drift check) may read this one role, which CI never writes.
  assert {
    condition = jsonencode(local.agent_read_statements) == jsonencode([{
      Sid      = "ReadAgentRole"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
      Resource = ["arn:aws:iam::111122223333:role/platform/demo-foundation-agent-role"]
    }])
    error_message = "The plan role may read exactly the agent role and only through read actions."
  }
  # The statement really reaches the plan role: the stack passes it on to the baseline.
  assert {
    condition     = contains([for s in jsondecode(module.baseline.plan_read_policy).Statement : s.Sid], "ReadAgentRole")
    error_message = "The plan role must be able to read the agent role."
  }
}


# The deploy role is off until var.deploy is set: no role and no extra read for the plan role.
run "no_deploy_role_without_deploy_variable" {
  command = apply

  assert {
    condition     = length(module.deploy_role) == 0 && length(local.deploy_read_statements) == 0
    error_message = "Without var.deploy the stack creates no deploy role and widens nothing."
  }
}

run "deploy_role_named_by_key_trusted_to_its_environment_and_read_by_the_plan_role_only" {
  command = apply

  variables {
    deploy = {
      github_repository_id = "1394609283"
      artifact_bucket      = "example-artifacts"
      artifact_prefix      = "testbed"
    }
  }

  assert {
    condition     = module.deploy_role[0].name == "demo-foundation-testbed-deploy-role"
    error_message = "The deploy role must be demo-foundation-testbed-deploy-role."
  }

  # One exact subject: the testbed's repository in the demo GitHub Environment of this account, through the baseline's provider.
  assert {
    condition     = jsondecode(module.deploy_role[0].trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:BuzzL@6116516/workforce-testbed@1394609283:environment:demo"
    error_message = "Only the testbed in the demo GitHub Environment may assume the deploy role."
  }

  # The plan role (drift check) may read this one role, which CI never writes.
  assert {
    condition = jsonencode(local.deploy_read_statements) == jsonencode([{
      Sid      = "ReadDeployRole"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
      Resource = ["arn:aws:iam::111122223333:role/platform/demo-foundation-testbed-deploy-role"]
    }])
    error_message = "The plan role may read exactly the deploy role and only through read actions."
  }

  assert {
    condition     = contains([for s in jsondecode(module.baseline.plan_read_policy).Statement : s.Sid], "ReadDeployRole")
    error_message = "The plan role must be able to read the deploy role."
  }
}

run "deploy_role_needs_a_numeric_repository_id" {
  command = plan

  variables {
    deploy = {
      github_repository_id = "not-a-number"
      artifact_bucket      = "example-artifacts"
      artifact_prefix      = "testbed"
    }
  }

  expect_failures = [var.deploy]
}
