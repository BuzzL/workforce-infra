# The deploy role of the test account (docs/ENVIRONMENT_PERMISSIONS.md): starts a CloudFormation
# deployment of the testbed through change sets and reads the result. Trusted through the GitHub
# OIDC provider of the baseline, to the testbed's repository in the test GitHub Environment.
# It lives in this baseline stack, applied locally, because CI has no IAM write permission
# (docs/ACCOUNT_CI_BASELINES.md, decision 2). Off until var.deploy is set.
locals {
  deploy_enabled = var.deploy != null

  # Public values (the owner is the one of the baseline's own defaults); the repository and its ID are set in var.deploy.
  deploy_owner    = "BuzzL"
  deploy_owner_id = "6116516"

  deploy_role_name = "test-foundation-testbed-deploy-role"
  # The plan role of CI reads the deploy role to check for drift, and nothing else of IAM.
  deploy_read_statements = local.deploy_enabled ? [{
    Sid      = "ReadDeployRole"
    Effect   = "Allow"
    Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
    Resource = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/platform/${local.deploy_role_name}"]
  }] : []
}

module "deploy_role" {
  source = "../../../modules/deploy-role"
  count  = local.deploy_enabled ? 1 : 0

  key                  = local.key
  stacks               = var.deploy.stacks
  region               = var.region
  account_id           = data.aws_caller_identity.current.account_id
  oidc_provider_arn    = module.baseline.oidc_provider_arn
  github_owner         = local.deploy_owner
  github_owner_id      = local.deploy_owner_id
  github_repository    = var.deploy.github_repository
  github_repository_id = var.deploy.github_repository_id
  artifact_bucket      = var.deploy.artifact_bucket
  artifact_prefix      = var.deploy.artifact_prefix
  tags                 = var.tags
}
