# The agent role of the demo account (docs/AGENT_ROLES.md): read only, assumed by the agent task
# role of workforce. It lives in this baseline stack, applied locally, because CI has no IAM write
# permission (docs/ACCOUNT_CI_BASELINES.md, decision 2). Off until var.agent is set.
locals {
  # Whether a role exists is not a secret, its ARNs are: nonsensitive() lets the switch drive count.
  agent_enabled = nonsensitive(var.agent != null)

  key = "demo"

  # The plan role of CI reads the agent role to check for drift, and nothing else of IAM.
  agent_role_name = "${local.key}-foundation-agent-role"
  agent_read_statements = local.agent_enabled ? [{
    Sid      = "ReadAgentRole"
    Effect   = "Allow"
    Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
    Resource = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/platform/${local.agent_role_name}"]
  }] : []
}

data "aws_caller_identity" "current" {}

module "agent_role" {
  source = "../../../modules/agent-role"
  count  = local.agent_enabled ? 1 : 0

  key                  = local.key
  region               = var.region
  account_id           = data.aws_caller_identity.current.account_id
  principal_arn        = var.agent.principal_arn
  workforce_account_id = var.agent.workforce_account_id
  external_ids         = var.agent.external_ids
  extra_principal_arns = var.agent.extra_principal_arns
  tags                 = var.tags
}
