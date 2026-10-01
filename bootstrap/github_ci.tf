# CI roles for workforce-github, the repository that manages GitHub as code (repos, rulesets,
# GitHub Environments). The GitHub provider is not AWS, so these roles can do two things
# only: reach the state of the one stack `live/github` and read the key of the GitHub App
# the provider authenticates as. No AWS resource is managed through them.
#
# The App keys are created by hand as SecureString parameters (never by Terraform: the key
# would end up in the state) and encrypted with the AWS managed key of SSM.
locals {
  github_ci_state_key = "live/github/terraform.tfstate"
  github_ci_sub       = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_ci_repository}@${var.github_ci_repository_id}:environment"

  github_ci_account_id = data.aws_caller_identity.current.account_id

  # Apply uses the App with write permissions, plan its own read-only App: only the apply role
  # can read the key that can change repositories.
  github_ci_roles = {
    apply = { name = "github-infra-github", environment = "github", parameter = "/workforce/github/app-write-key" }
    plan  = { name = "github-infra-github-plan", environment = "github-plan", parameter = "/workforce/github/app-read-key" }
  }
  github_ci_parameter_arns = {
    for k, r in local.github_ci_roles : k => "arn:aws:ssm:${var.region}:${local.github_ci_account_id}:parameter${r.parameter}"
  }

  # What a plan of this file's resources reads, shared by the management roles that plan bootstrap.
  github_ci_role_arns = [for r in aws_iam_role.github_ci : r.arn]
}

# Trusted by exactly one subject each: workflows of one repository in one GitHub Environment.
# StringEquals, never StringLike. The `github` environment is protected (reviewer, main only);
# `github-plan` has no reviewer, so its role must stay read-only.
resource "aws_iam_role" "github_ci" {
  for_each = local.github_ci_roles

  name                 = each.value.name
  description          = "Assumed by ${var.github_owner}/${var.github_ci_repository} CI in the ${each.value.environment} environment."
  max_session_duration = 3600

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
            "token.actions.githubusercontent.com:sub" = "${local.github_ci_sub}:${each.value.environment}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policies_exclusive" "github_ci" {
  for_each = local.github_ci_roles

  role_name = aws_iam_role.github_ci[each.key].name
  policy_names = [
    aws_iam_role_policy.github_ci_state[each.key].name,
    aws_iam_role_policy.github_ci_app_key[each.key].name,
  ]
}

resource "aws_iam_role_policy_attachments_exclusive" "github_ci" {
  for_each = local.github_ci_roles

  role_name   = aws_iam_role.github_ci[each.key].name
  policy_arns = []
}

# State of live/github only. The apply role also takes the lockfile; the plan role is read-only
# (plans run with -lock=false). ListBucket is not narrowed by prefix, like the management roles:
# without it S3 answers 403 instead of "not found" for a state object that does not exist yet, and
# `terraform init` lists the `env:/` prefix. It shows key names only, never contents.
resource "aws_iam_role_policy" "github_ci_state" {
  for_each = local.github_ci_roles

  name = "terraform-state"
  role = aws_iam_role.github_ci[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ListStateBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = [local.state_bucket_arn]
        },
        {
          Sid      = each.key == "apply" ? "ReadAndWriteState" : "ReadState"
          Effect   = "Allow"
          Action   = each.key == "apply" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"]
          Resource = ["${local.state_bucket_arn}/${local.github_ci_state_key}"]
        },
      ],
      each.key == "apply" ? [
        {
          Sid      = "LockState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = ["${local.state_bucket_arn}/${local.github_ci_state_key}.tflock"]
        },
      ] : []
    )
  })
}

# The key of the GitHub App, read through SSM. Decrypting a SecureString that uses the AWS
# managed key needs kms:Decrypt; the key ID is not known to Terraform, so the resource is
# every key of this account in this region, narrowed to calls made by SSM for exactly this
# parameter (the encryption context carries its ARN).
resource "aws_iam_role_policy" "github_ci_app_key" {
  for_each = local.github_ci_roles

  name = "github-app-key"
  role = aws_iam_role.github_ci[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAppKeyParameter"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [local.github_ci_parameter_arns[each.key]]
      },
      {
        Sid      = "DecryptAppKeyThroughSsm"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = ["arn:aws:kms:${var.region}:${local.github_ci_account_id}:key/*"]
        Condition = {
          StringEquals = {
            "kms:ViaService"                      = "ssm.${var.region}.amazonaws.com"
            "kms:EncryptionContext:PARAMETER_ARN" = local.github_ci_parameter_arns[each.key]
          }
        }
      },
    ]
  })
}
