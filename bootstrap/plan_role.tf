locals {
  # Not a variable, for the same reason as github_environment.
  github_plan_environment = "management-plan"
  github_plan_sub         = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:environment:${local.github_plan_environment}"
}

# Read-only role for the plans that run on pull requests. It is trusted by the
# management-plan environment, which has no reviewer and accepts any branch, so it must
# never be able to write: no lockfile (plans run with -lock=false), no state writes, no
# IAM or S3 changes. Anyone who can push a branch here can run code with these reads.
resource "aws_iam_role" "github_infra_management_plan" {
  name                 = "github-infra-management-plan"
  description          = "Read-only plans for ${var.github_owner}/${var.github_repository} pull requests in the ${local.github_plan_environment} environment."
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
            "token.actions.githubusercontent.com:sub" = local.github_plan_sub
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policies_exclusive" "github_infra_management_plan" {
  role_name = aws_iam_role.github_infra_management_plan.name
  policy_names = concat([
    aws_iam_role_policy.plan_state_read.name,
    aws_iam_role_policy.plan_bootstrap_read.name,
    aws_iam_role_policy.plan_organization_units.name,
    aws_iam_role_policy.plan_budget.name,
  ], [for p in aws_iam_role_policy.plan_audit_trail : p.name])
}

resource "aws_iam_role_policy_attachments_exclusive" "github_infra_management_plan" {
  role_name   = aws_iam_role.github_infra_management_plan.name
  policy_arns = []
}

# Read the state of the bootstrap and live/management stacks only, not every stack: this role
# is open to any branch, and the state of a stack can hold secret values (the account emails
# of a later stack must stay out of this list). Its Organizations reads let branch code list
# the member accounts of an OU (ListAccountsForParent), which is accepted: a branch needs
# write access to this repository, and fork pull requests get no token. The Organizations reads below also list the
# member accounts of an OU (ListAccountsForParent), so code on any branch can enumerate
# account IDs: accepted for this PoC, since pushing a branch needs write access. Read only: there is no lock write, so plans on
# pull requests must use -lock=false.
resource "aws_iam_role_policy" "plan_state_read" {
  name = "terraform-state-read"
  role = aws_iam_role.github_infra_management_plan.id

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
        Sid      = "ReadManagementState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.state_bucket_arn}/live/management/terraform.tfstate"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "plan_bootstrap_read" {
  name = "plan-bootstrap-stack"
  role = aws_iam_role.github_infra_management_plan.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.bootstrap_read_statements
  })
}

resource "aws_iam_role_policy" "plan_organization_units" {
  name = "plan-organization-units"
  role = aws_iam_role.github_infra_management_plan.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.organization_read_statements
  })
}
