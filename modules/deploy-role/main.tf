# The deploy role of docs/ENVIRONMENT_PERMISSIONS.md: it only starts a CloudFormation deployment of
# one application (change sets, with one execution role and one artifact) and reads the result.
# Trusted through GitHub OIDC, one exact subject: the application's repository in the GitHub
# Environment of this account. The execution role holds the permissions that create resources.
locals {
  environments = { test = "test", qual = "quality", demo = "demo" }
  environment  = local.environments[var.key]

  prefix = "arn:aws:%s:${var.region}:${var.account_id}:%s"
  base   = "${var.key}-${var.project}-${var.application}"

  # test: any stack of the application. quality and demo: exactly the registered ones.
  stacks = var.key == "test" ? [format(local.prefix, "cloudformation", "stack/${local.base}-*-stack/*")] : [
    for q in var.stacks : format(local.prefix, "cloudformation", "stack/${local.base}-${q}-stack/*")
  ]
  functions = [
    format(local.prefix, "lambda", "function:${local.base}-*-function"),
    format(local.prefix, "lambda", "function:${local.base}-*-function:*"),
  ]
  alarms   = [format(local.prefix, "cloudwatch", "alarm:${local.base}-*-alarm")]
  artifact = ["arn:aws:s3:::${var.artifact_bucket}/${var.artifact_prefix}/*"]

  exec_role_arn = "arn:aws:iam::${var.account_id}:role/platform/${local.base}-exec-role"
  template_url  = "https://${var.artifact_bucket}.s3.${var.region}.amazonaws.com/${var.artifact_prefix}/*"

  # The keys of docs/TAG_CONVENTION.md: the pipeline sets these and no others.
  tag_keys = ["App", "Archetype", "Environment", "ManagedBy", "Project", "Repository", "Stack", "Target"]

  # A stack cannot be created without its tags (no condition key tells a create from an update),
  # so a create carries the execution role, the artifact and the two literal tags. One StringEquals
  # block: merge() is shallow and would let the tags replace the role condition.
  exec_role_only = { StringEquals = { "cloudformation:RoleArn" = [local.exec_role_arn] } }
  from_artifact  = { StringLike = { "cloudformation:TemplateUrl" = [local.template_url] } }
  on_create = {
    StringEquals = {
      "cloudformation:RoleArn"     = [local.exec_role_arn]
      "aws:RequestTag/App"         = [var.application]
      "aws:RequestTag/Environment" = [local.environment]
    }
    StringLike = { "cloudformation:TemplateUrl" = [local.template_url] }
  }

  # test deploys every pull request, so it creates and deletes ephemeral stacks. quality and demo never do.
  create_and_delete = var.key != "test" ? [] : [
    {
      sid        = "CreateStacks"
      actions    = ["cloudformation:CreateStack"]
      resources  = local.stacks
      conditions = local.on_create
    },
    {
      sid        = "DeleteStacks"
      actions    = ["cloudformation:DeleteStack"]
      resources  = local.stacks
      conditions = local.exec_role_only
    },
  ]
}

module "role" {
  source = "../cross-account-role"

  name        = "${local.base}-deploy-role"
  description = "Deploys ${var.application} into the ${local.environment} account through change sets. Assumed by ${var.github_owner}/${var.github_repository} in the ${local.environment} GitHub Environment."
  tags        = var.tags

  trust = {
    mode = "web_identity"
    web_identity = {
      provider_arn = var.oidc_provider_arn
      subject      = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:environment:${local.environment}"
    }
  }

  statements = concat(local.create_and_delete, [
    {
      sid        = "CreateChangeSets"
      actions    = ["cloudformation:CreateChangeSet"]
      resources  = local.stacks
      conditions = local.on_create
    },
    {
      sid = "FollowChangeSets"
      actions = [
        "cloudformation:ExecuteChangeSet", "cloudformation:DeleteChangeSet", "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents", "cloudformation:DescribeChangeSet", "cloudformation:GetTemplate",
      ]
      resources = local.stacks
    },
    {
      sid                 = "ReadTemplateSummary"
      actions             = ["cloudformation:GetTemplateSummary"]
      resources           = ["*"]
      conditions          = local.from_artifact
      any_resource_reason = "GetTemplateSummary on a template URL has no stack to name; it is narrowed to the artifact prefix by cloudformation:TemplateUrl."
    },
    {
      sid       = "TagStacks"
      actions   = ["cloudformation:TagResource", "cloudformation:UntagResource"]
      resources = local.stacks
      conditions = {
        "ForAllValues:StringEquals" = { "aws:TagKeys" = local.tag_keys }
      }
    },
    {
      sid        = "PassExecutionRole"
      actions    = ["iam:PassRole"]
      resources  = [local.exec_role_arn]
      conditions = { StringEquals = { "iam:PassedToService" = ["cloudformation.amazonaws.com"] } }
    },
    {
      sid       = "ReadArtifact"
      actions   = ["s3:GetObject"]
      resources = local.artifact
    },
    {
      sid       = "CheckFunctions"
      actions   = ["lambda:GetFunctionConfiguration", "lambda:GetAlias"]
      resources = local.functions
    },
    {
      sid       = "CheckAlarms"
      actions   = ["cloudwatch:DescribeAlarms"]
      resources = local.alarms
    },
  ])
}
