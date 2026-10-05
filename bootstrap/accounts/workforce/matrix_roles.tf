# The matrix runner roles (docs/AGENT_ROLES.md): the identity of the permission matrix job of
# workforce-infra (.github/workflows/permission-matrix.yml). One role per environment, trusted by
# GitHub OIDC for exactly one subject: this repository in the <environment>-matrix GitHub
# Environment. Each may assume the agent role of its own environment and nothing else; that agent
# role trusts it in return (modules/agent-role, extra_principal_arns). Off until var.matrix is set.
# Applied locally, like the rest of the baseline (docs/ACCOUNT_CI_BASELINES.md, decision 2).
locals {
  # Whether a role exists is not a secret, its ARNs are: nonsensitive() lets the switch drive for_each.
  matrix_enabled = nonsensitive(var.matrix != null)

  # GitHub Environment prefix and the key of the environment account (scripts/environment-keys.tsv).
  matrix_environments = { test = "test", quality = "qual", demo = "demo" }
  matrix_role_names   = { for env, key in local.matrix_environments : env => "wrkf-foundation-matrix-${env}-role" }

  # The plan role of CI reads the runner roles to check for drift, and nothing else of IAM.
  matrix_read_statements = local.matrix_enabled ? [{
    Sid      = "ReadMatrixRoles"
    Effect   = "Allow"
    Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
    Resource = [for env, name in local.matrix_role_names : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/platform/${name}"]
  }] : []
}

module "matrix_role" {
  source   = "../../../modules/cross-account-role"
  for_each = local.matrix_enabled ? local.matrix_environments : {}

  name        = local.matrix_role_names[each.key]
  description = "Assumed by the permission matrix job of workforce-infra in the ${each.key}-matrix GitHub Environment. May assume the ${each.key} agent role only."
  tags        = var.tags

  trust = {
    mode = "web_identity"
    web_identity = {
      provider_arn = module.baseline.oidc_provider_arn
      subject      = "${module.baseline.github_subject_prefix}:${each.key}-matrix"
    }
  }

  statements = [{
    sid       = "AssumeTheAgentRole"
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${var.matrix.environment_account_ids[each.key]}:role/platform/${each.value}-foundation-agent-role"]
  }]
}
