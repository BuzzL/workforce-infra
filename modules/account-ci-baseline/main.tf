data "aws_caller_identity" "current" {}

locals {
  # Commercial partition only: this repo does not target GovCloud or China.
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
  account_id       = data.aws_caller_identity.current.account_id

  github_sub_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:environment"
  apply_environment = var.account_name
  plan_environment  = "${var.account_name}-plan"

  apply_role_name = "github-infra-${var.account_name}"
  plan_role_name  = "github-infra-${var.account_name}-plan"

  # What the stack manages: this provider and these two roles. Read-only, on exactly them.
  baseline_read_statements = [
    {
      Sid      = "ReadBaselineProvider"
      Effect   = "Allow"
      Action   = ["iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviderTags"]
      Resource = [aws_iam_openid_connect_provider.github.arn]
    },
    {
      Sid      = "ReadBaselineRoles"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
      Resource = ["arn:aws:iam::${local.account_id}:role/${local.apply_role_name}", "arn:aws:iam::${local.account_id}:role/${local.plan_role_name}"]
    },
  ]
}

# One OIDC provider per account. No thumbprint: AWS validates GitHub's certificate chain
# against its trusted CAs.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

# Trusted by exactly one subject: workflows of one repository running in one GitHub
# Environment. StringEquals, never StringLike, so there is no wildcard to widen.
resource "aws_iam_role" "apply" {
  name                 = local.apply_role_name
  description          = "Assumed by ${var.github_owner}/${var.github_repository} CI in the ${local.apply_environment} environment."
  max_session_duration = 3600
  tags                 = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "${local.github_sub_prefix}:${local.apply_environment}"
          }
        }
      }
    ]
  })
}

# Terraform owns the role's permissions completely: anything attached outside these
# resources is removed on the next apply.
resource "aws_iam_role_policies_exclusive" "apply" {
  role_name    = aws_iam_role.apply.name
  policy_names = [aws_iam_role_policy.apply_state.name, aws_iam_role_policy.apply_baseline_read.name]
}

resource "aws_iam_role_policy_attachments_exclusive" "apply" {
  role_name   = aws_iam_role.apply.name
  policy_arns = []
}

# State and native lockfile of this stack only. The apply role cannot change IAM: the
# baseline itself is changed through the break-glass bootstrap, never by CI, so CI cannot
# widen its own permissions.
# s3:prefix "env:/": `terraform init` lists the workspaces of the S3 backend with that prefix,
# and fails with AccessDenied if the listing is not allowed. It exposes key names only.
resource "aws_iam_role_policy" "apply_state" {
  name = "terraform-state"
  role = aws_iam_role.apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
        Condition = {
          StringEquals = { "s3:prefix" = ["env:/", var.state_key, "${var.state_key}.tflock"] }
        }
      },
      {
        Sid      = "ReadAndWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["${local.state_bucket_arn}/${var.state_key}"]
      },
      {
        Sid      = "LockState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/${var.state_key}.tflock"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "apply_baseline_read" {
  name = "baseline-read"
  role = aws_iam_role.apply.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.baseline_read_statements
  })
}

# Read-only role for the plans that run on pull requests. Its environment has no reviewer
# and accepts any branch, so it must never write: no lockfile (plans run with -lock=false),
# no state writes, no IAM changes.
resource "aws_iam_role" "plan" {
  name                 = local.plan_role_name
  description          = "Read-only plans for ${var.github_owner}/${var.github_repository} pull requests in the ${local.plan_environment} environment."
  max_session_duration = 3600
  tags                 = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "${local.github_sub_prefix}:${local.plan_environment}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policies_exclusive" "plan" {
  role_name    = aws_iam_role.plan.name
  policy_names = [aws_iam_role_policy.plan_state_read.name, aws_iam_role_policy.plan_baseline_read.name]
}

resource "aws_iam_role_policy_attachments_exclusive" "plan" {
  role_name   = aws_iam_role.plan.name
  policy_arns = []
}

resource "aws_iam_role_policy" "plan_state_read" {
  name = "terraform-state-read"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
        Condition = {
          StringEquals = { "s3:prefix" = ["env:/", var.state_key] }
        }
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.state_bucket_arn}/${var.state_key}"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "plan_baseline_read" {
  name = "baseline-read"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.baseline_read_statements
  })
}
