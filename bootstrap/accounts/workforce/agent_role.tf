# The agent task role: the one principal the agent roles of the test, quality and demo accounts
# trust (docs/AGENT_ROLES.md). The ECS service assumes it for the agent's tasks. It starts with no
# permissions; each one is added with its reason by the change that needs it (the ECS stack
# IAT-60 and the permission to assume the three agent roles). Applied locally with the rest of
# the baseline, because CI has no IAM write (docs/ACCOUNT_CI_BASELINES.md, decision 2).
data "aws_caller_identity" "current" {}

locals {
  agent_role_name = "wrkf-foundation-agent-role"

  # The plan role of CI reads this one role to check for drift, and nothing else of IAM.
  agent_read_statements = [{
    Sid      = "ReadAgentTaskRole"
    Effect   = "Allow"
    Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
    Resource = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/platform/${local.agent_role_name}"]
  }]
}

module "agent_role" {
  source = "../../../modules/cross-account-role"

  name        = local.agent_role_name
  description = "Assumed by the ECS tasks of the developer agent. Starts with no permissions."
  tags        = var.tags

  trust = {
    mode = "service"
    service = {
      principal          = "ecs-tasks.amazonaws.com"
      source_account_id  = data.aws_caller_identity.current.account_id
      source_arn_pattern = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task/*"
    }
  }
}
