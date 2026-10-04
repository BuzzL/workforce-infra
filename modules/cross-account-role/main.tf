locals {
  trust = var.trust

  assume_role_policy = local.trust.mode != "assume_role" ? "" : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = local.trust.assume_role.principal_arn }
      Action    = "sts:AssumeRole"
      Condition = merge(
        {
          # The principal ARN is already exact; the account and the ARN conditions repeat it on
          # purpose, so that no later edit of the Principal alone can widen the trust.
          StringEquals = {
            "aws:PrincipalAccount" = local.trust.assume_role.source_account_id
            "sts:ExternalId"       = local.trust.assume_role.external_ids
          }
          ArnEquals = { "aws:PrincipalArn" = local.trust.assume_role.principal_arn }
        },
        try(local.trust.assume_role.session_name_pattern, null) == null ? {} : {
          StringLike = { "sts:RoleSessionName" = local.trust.assume_role.session_name_pattern }
        },
      )
    }]
  })

  web_identity_policy = local.trust.mode != "web_identity" ? "" : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.trust.web_identity.provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${regex("oidc-provider/(.+)$", local.trust.web_identity.provider_arn)[0]}:aud" = local.trust.web_identity.audience
          "${regex("oidc-provider/(.+)$", local.trust.web_identity.provider_arn)[0]}:sub" = local.trust.web_identity.subject
        }
      }
    }]
  })

  service_policy = local.trust.mode != "service" ? "" : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = local.trust.service.principal }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.trust.service.source_account_id }
        ArnLike      = { "aws:SourceArn" = local.trust.service.source_arn_pattern }
      }
    }]
  })

  trust_policy = coalesce(local.assume_role_policy, local.web_identity_policy, local.service_policy)

  policy_statements = [for s in var.statements : merge(
    {
      Sid      = s.sid
      Effect   = s.effect
      Action   = s.actions
      Resource = s.resources
    },
    length(s.conditions) == 0 ? {} : { Condition = s.conditions },
  )]
}

resource "aws_iam_role" "this" {
  name                 = var.name
  path                 = var.path
  description          = var.description
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags

  assume_role_policy = local.trust_policy
}

# Terraform owns the role's permissions completely: anything attached outside this module
# is removed on the next apply.
resource "aws_iam_role_policies_exclusive" "this" {
  role_name    = aws_iam_role.this.name
  policy_names = aws_iam_role_policy.permissions[*].name
}

resource "aws_iam_role_policy_attachments_exclusive" "this" {
  role_name   = aws_iam_role.this.name
  policy_arns = []
}

resource "aws_iam_role_policy" "permissions" {
  count = length(var.statements) > 0 ? 1 : 0

  name = "permissions"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.policy_statements
  })
}
