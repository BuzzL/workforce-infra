# The CDK deployment of workforce-pipeline into this account (docs/CDK_BOOTSTRAP.md): a deploy
# role for its CI, the CloudFormation execution role it passes, and the permissions boundary of
# every role the pipeline's stacks create. No AdministratorAccess and no cdk-* roles: the CDK app
# synthesizes with CliCredentialsStackSynthesizer and deploys with --role-arn <execution role>.
# Applied locally, like the rest of the baseline, because CI has no IAM write
# (docs/ACCOUNT_CI_BASELINES.md, decision 2). Off until var.pipeline is set.
locals {
  pipeline_enabled = var.pipeline != null

  pipeline_account = data.aws_caller_identity.current.account_id
  pipeline_base    = "wrkf-foundation-pipeline"

  pipeline_deploy_role_name = "${local.pipeline_base}-deploy-role"
  pipeline_exec_role_name   = "${local.pipeline_base}-exec-role"
  pipeline_boundary_name    = "${local.pipeline_base}-boundary"

  pipeline_exec_role_arn = "arn:aws:iam::${local.pipeline_account}:role/platform/${local.pipeline_exec_role_name}"
  pipeline_boundary_arn  = "arn:aws:iam::${local.pipeline_account}:policy/platform/${local.pipeline_boundary_name}"

  # Public values, as in the baselines of the environment accounts.
  pipeline_owner    = "BuzzL"
  pipeline_owner_id = "6116516"

  pipeline_stacks    = "arn:aws:cloudformation:${var.region}:${local.pipeline_account}:stack/${local.pipeline_base}-*-stack/*"
  pipeline_app_roles = "arn:aws:iam::${local.pipeline_account}:role/apps/pipeline/${local.pipeline_base}-*-role"

  # The staging bucket and stack of the custom bootstrap. The qualifier is CDK's, at most 10 characters.
  cdk_qualifier      = "wrkf"
  cdk_toolkit_stack  = "wrkf-foundation-cdktoolkit-stack"
  cdk_assets_bucket  = "cdk-${local.cdk_qualifier}-assets-${local.pipeline_account}-${var.region}"
  cdk_assets_arn     = "arn:aws:s3:::${local.cdk_assets_bucket}"
  cdk_template_urls  = ["https://s3.${var.region}.amazonaws.com/${local.cdk_assets_bucket}/*", "https://${local.cdk_assets_bucket}.s3.${var.region}.amazonaws.com/*"]
  pipeline_tag_keys  = ["App", "Archetype", "Environment", "ManagedBy", "Project", "Repository", "Stack", "Target"]
  pipeline_tag_rules = { "ForAllValues:StringEquals" = { "aws:TagKeys" = local.pipeline_tag_keys } }

  # The boundary: everything a role of the pipeline's stacks may ever do. Writing its own Lambda
  # log streams, and nothing else until a workload needs more (each addition is approved).
  pipeline_boundary_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteOwnFunctionLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = ["arn:aws:logs:${var.region}:${local.pipeline_account}:log-group:/aws/lambda/${local.pipeline_base}-*-function:*"]
    }]
  }

  # The plan role of CI reads the two roles and the boundary to check for drift, and nothing else of IAM.
  pipeline_read_statements = local.pipeline_enabled ? [
    {
      Sid      = "ReadPipelineRoles"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
      Resource = ["arn:aws:iam::${local.pipeline_account}:role/platform/${local.pipeline_deploy_role_name}", local.pipeline_exec_role_arn]
    },
    {
      Sid      = "ReadPipelineBoundary"
      Effect   = "Allow"
      Action   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListPolicyTags"]
      Resource = [local.pipeline_boundary_arn]
    },
  ] : []
}

resource "aws_iam_policy" "pipeline_boundary" {
  count = local.pipeline_enabled ? 1 : 0

  name        = local.pipeline_boundary_name
  path        = "/platform/"
  description = "Permissions boundary of every role the stacks of workforce-pipeline create."
  policy      = jsonencode(local.pipeline_boundary_policy)
}

module "pipeline_exec_role" {
  source = "../../../modules/cross-account-role"
  count  = local.pipeline_enabled ? 1 : 0

  name        = local.pipeline_exec_role_name
  description = "Passed to CloudFormation by the workforce-pipeline deploy role. Creates the stacks' resources; roles only under /apps/pipeline/ and with the boundary."
  tags        = var.tags

  trust = {
    mode = "service"
    service = {
      principal          = "cloudformation.amazonaws.com"
      source_account_id  = local.pipeline_account
      source_arn_pattern = local.pipeline_stacks
    }
  }

  statements = [
    {
      sid        = "CreateBoundedRoles"
      actions    = ["iam:CreateRole", "iam:PutRolePolicy"]
      resources  = [local.pipeline_app_roles]
      conditions = { StringEquals = { "iam:PermissionsBoundary" = [local.pipeline_boundary_arn] } }
    },
    {
      sid = "MaintainAppRoles"
      actions = [
        "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:DeleteRolePolicy", "iam:DeleteRole",
      ]
      resources = [local.pipeline_app_roles]
    },
    {
      sid        = "TagAppRoles"
      actions    = ["iam:TagRole", "iam:UntagRole"]
      resources  = [local.pipeline_app_roles]
      conditions = local.pipeline_tag_rules
    },
  ]
}

module "pipeline_deploy_role" {
  source = "../../../modules/cross-account-role"
  count  = local.pipeline_enabled ? 1 : 0

  name        = local.pipeline_deploy_role_name
  description = "Deploys workforce-pipeline through CloudFormation change sets with its execution role. Assumed by ${local.pipeline_owner}/workforce-pipeline in the workforce GitHub Environment."
  tags        = var.tags

  trust = {
    mode = "web_identity"
    web_identity = {
      provider_arn = module.baseline.oidc_provider_arn
      subject      = "repo:${local.pipeline_owner}@${local.pipeline_owner_id}/workforce-pipeline@${var.pipeline.github_repository_id}:environment:workforce"
    }
  }

  statements = [
    {
      sid       = "CreateChangeSets"
      actions   = ["cloudformation:CreateChangeSet"]
      resources = [local.pipeline_stacks]
      conditions = {
        StringEquals = { "cloudformation:RoleArn" = [local.pipeline_exec_role_arn] }
        StringLike   = { "cloudformation:TemplateUrl" = local.cdk_template_urls }
      }
    },
    {
      sid = "FollowChangeSets"
      actions = [
        "cloudformation:ExecuteChangeSet", "cloudformation:DeleteChangeSet", "cloudformation:DescribeChangeSet",
        "cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents", "cloudformation:GetTemplate",
      ]
      resources = [local.pipeline_stacks]
    },
    {
      sid        = "TagStacks"
      actions    = ["cloudformation:TagResource", "cloudformation:UntagResource"]
      resources  = [local.pipeline_stacks]
      conditions = local.pipeline_tag_rules
    },
    {
      sid       = "ReadToolkitStack"
      actions   = ["cloudformation:DescribeStacks"]
      resources = ["arn:aws:cloudformation:${var.region}:${local.pipeline_account}:stack/${local.cdk_toolkit_stack}/*"]
    },
    {
      sid        = "PassExecutionRole"
      actions    = ["iam:PassRole"]
      resources  = [local.pipeline_exec_role_arn]
      conditions = { StringEquals = { "iam:PassedToService" = ["cloudformation.amazonaws.com"] } }
    },
    {
      sid       = "CheckAssetBucket"
      actions   = ["s3:GetBucketLocation", "s3:GetEncryptionConfiguration", "s3:ListBucket"]
      resources = [local.cdk_assets_arn]
    },
    {
      sid       = "PublishAssets"
      actions   = ["s3:PutObject", "s3:GetObject"]
      resources = ["${local.cdk_assets_arn}/*"]
    },
  ]
}
