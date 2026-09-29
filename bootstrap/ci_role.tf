locals {
  # Not a variable: a local tfvars file must not be able to point the trust at an unprotected environment.
  github_environment = "management"

  # GitHub issues immutable subjects for this repository: repo:<owner>@<owner id>/<repo>@<repo id>.
  # Check the current format with: gh api repos/<owner>/<repo>/actions/oidc/customization/sub
  github_sub = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:environment:${local.github_environment}"
}

# Trusted by exactly one subject: workflows of one repository running in one GitHub
# Environment. StringEquals, never StringLike, so there is no wildcard to widen.
resource "aws_iam_role" "github_infra_management" {
  name                 = "github-infra-management"
  description          = "Assumed by ${var.github_owner}/${var.github_repository} CI in the ${local.github_environment} environment."
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
            "token.actions.githubusercontent.com:sub" = local.github_sub
          }
        }
      }
    ]
  })
}

# Terraform owns the role's permissions completely: any inline policy or managed policy
# attached outside these resources is removed on the next apply.
resource "aws_iam_role_policies_exclusive" "github_infra_management" {
  role_name    = aws_iam_role.github_infra_management.name
  policy_names = [aws_iam_role_policy.state_access.name, aws_iam_role_policy.plan_bootstrap.name]
}

resource "aws_iam_role_policy_attachments_exclusive" "github_infra_management" {
  role_name   = aws_iam_role.github_infra_management.name
  policy_arns = []
}

# This stack's own state (read only: it is applied locally) and its native lockfile.
resource "aws_iam_role_policy" "state_access" {
  name = "terraform-state"
  role = aws_iam_role.github_infra_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
      },
      {
        Sid      = "ReadBootstrapState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.state_bucket_arn}/bootstrap/terraform.tfstate"] # key of backend.hcl
      },
      {
        Sid      = "LockBootstrapState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/bootstrap/terraform.tfstate.tflock"]
      }
    ]
  })
}

# Read-only on the resources this stack manages.
resource "aws_iam_role_policy" "plan_bootstrap" {
  name = "plan-bootstrap-stack"
  role = aws_iam_role.github_infra_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadStateBucketConfiguration"
        Effect = "Allow"
        Action = [
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketLogging",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketOwnershipControls",
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketTagging",
          "s3:GetBucketVersioning",
          "s3:GetBucketWebsite",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
        ]
        Resource = [local.state_bucket_arn]
      },
      {
        Sid    = "ReadGithubProviderAndRole"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListOpenIDConnectProviderTags",
          "iam:ListRolePolicies",
          "iam:ListRoleTags",
        ]
        Resource = [
          aws_iam_openid_connect_provider.github.arn,
          aws_iam_role.github_infra_management.arn,
        ]
      }
    ]
  })
}
