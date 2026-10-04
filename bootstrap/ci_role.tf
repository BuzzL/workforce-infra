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
  role_name = aws_iam_role.github_infra_management.name
  policy_names = concat([
    aws_iam_role_policy.state_access.name,
    aws_iam_role_policy.plan_bootstrap.name,
    aws_iam_role_policy.organization_units.name,
    aws_iam_role_policy.budget.name,
    aws_iam_role_policy.service_control_policies.name,
  ], [for p in aws_iam_role_policy.audit_trail : p.name])
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
        Sid      = "ReadAndWriteManagementState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["${local.state_bucket_arn}/live/management/terraform.tfstate"]
      },
      {
        Sid      = "LockManagementState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/live/management/terraform.tfstate.tflock"]
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
    Version   = "2012-10-17"
    Statement = local.bootstrap_read_statements
  })
}

# Manages organizational units, and nothing else in Organizations: no accounts, no policies,
# no service access. Deleting OUs is allowed on purpose: the stack owns them. Writes are limited to OUs of this management account's Organization;
# the new OU's ARN is not known before the call, hence the ou-* pattern.
resource "aws_iam_role_policy" "organization_units" {
  name = "organization-units"
  role = aws_iam_role.github_infra_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.organization_read_statements, [
      {
        Sid    = "ManageOrganizationalUnits"
        Effect = "Allow"
        Action = [
          "organizations:CreateOrganizationalUnit",
          "organizations:UpdateOrganizationalUnit",
          "organizations:DeleteOrganizationalUnit",
          "organizations:TagResource",
          "organizations:UntagResource",
        ]
        Resource = [local.organization_root_arn_pattern, local.organization_ou_arn_pattern]
      }
    ])
  })
}

# No permission to assume OrganizationAccountAccessRole (or any role) in a member account: it is full
# administrator there, so with it a CI job could rewrite the baseline that limits CI. The
# one-time bootstrap and the recovery run locally, with the maintainer's own session
# (docs/ACCOUNT_CI_BASELINES.md, "Break-glass"). Asserted in tests/bootstrap.tftest.hcl.

# What a plan of this stack reads: shared by the management role and the plan role.
locals {
  bootstrap_read_statements = [
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
        "s3:ListTagsForResource",
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
      Resource = concat([
        aws_iam_openid_connect_provider.github.arn,
        aws_iam_role.github_infra_management.arn,
        aws_iam_role.github_infra_management_plan.arn,
      ], local.github_ci_role_arns)
    },
    # The one Organizations read that has no resource: the Identity Center delegation
    # (identity.tf). It lists delegated administrators; the registration itself is applied
    # locally, so neither role can register or remove one.
    {
      Sid      = "ReadDelegatedAdministrators"
      Effect   = "Allow"
      Action   = ["organizations:ListDelegatedAdministrators"]
      Resource = "*"
    }
  ]
}
