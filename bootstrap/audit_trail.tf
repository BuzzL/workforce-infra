# What CI needs for the organization trail of live/management (docs/AUDIT_LOGGING.md). On by
# default, because CI plans this stack without any local variable; set audit_trail_enabled to
# false only to take the grants away on purpose.
locals {
  # Must equal the default name of modules/organization-trail, which the log bucket policy
  # also names in its trail ARN.
  audit_trail_name = "workforce-organization"
  audit_trail_arn  = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.audit_trail_name}"

  # Reads of the trail, on exactly it. DescribeTrails has no resource-level permission.
  audit_trail_read_statements = [
    {
      Sid      = "ReadOrganizationTrail"
      Effect   = "Allow"
      Action   = ["cloudtrail:GetTrail", "cloudtrail:GetTrailStatus", "cloudtrail:GetEventSelectors", "cloudtrail:GetInsightSelectors", "cloudtrail:ListTags"]
      Resource = [local.audit_trail_arn]
    },
    {
      Sid      = "DescribeTrails"
      Effect   = "Allow"
      Action   = ["cloudtrail:DescribeTrails"]
      Resource = ["*"]
    },
  ]
}

# Creates and updates the one trail, and starts logging. There is deliberately no
# cloudtrail:DeleteTrail and no cloudtrail:StopLogging: CI cannot delete the trail or stop it,
# only an admin session can. UpdateTrail can still alter it (another bucket, validation off),
# so a change to the trail is only as safe as the review of its PR and the approval of the
# `management` environment. Enabling trusted access for CloudTrail in the
# Organization is a manual step (organizations:EnableAWSServiceAccess is not granted).
resource "aws_iam_role_policy" "audit_trail" {
  count = var.audit_trail_enabled ? 1 : 0

  name = "audit-trail"
  role = aws_iam_role.github_infra_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.audit_trail_read_statements, [
      {
        Sid      = "ManageOrganizationTrail"
        Effect   = "Allow"
        Action   = ["cloudtrail:CreateTrail", "cloudtrail:UpdateTrail", "cloudtrail:StartLogging", "cloudtrail:AddTags", "cloudtrail:RemoveTags"]
        Resource = [local.audit_trail_arn]
      },
      {
        Sid      = "ReadOrganizationForTheTrail"
        Effect   = "Allow"
        Action   = ["organizations:DescribeOrganization", "organizations:ListAWSServiceAccessForOrganization"]
        Resource = ["*"] # no resource-level permission; read only
      },
      {
        Sid      = "CreateTheCloudTrailServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/cloudtrail.amazonaws.com/AWSServiceRoleForCloudTrail"]
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "cloudtrail.amazonaws.com" }
        }
      },
    ])
  })
}

resource "aws_iam_role_policy" "plan_audit_trail" {
  count = var.audit_trail_enabled ? 1 : 0

  name = "plan-audit-trail"
  role = aws_iam_role.github_infra_management_plan.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.audit_trail_read_statements
  })
}
