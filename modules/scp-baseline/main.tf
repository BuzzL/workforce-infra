# Baseline service control policies (SCPs). The module only DEFINES them: it creates the
# policies and attaches none. Attaching is a separate, staged step (IAT-36), because an SCP
# that is wrong can lock principals out. Every statement is a Deny.

locals {
  policies = {
    deny-leave-organization = {
      description = "Member accounts cannot leave the Organization."
      statement = {
        Sid      = "DenyLeaveOrganization"
        Effect   = "Deny"
        Action   = ["organizations:LeaveOrganization"]
        Resource = "*"
      }
    }

    deny-root-user = {
      description = "The root user of a member account cannot do anything."
      statement = {
        Sid      = "DenyRootUser"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringLike = { "aws:PrincipalArn" = "arn:aws:iam::*:root" }
        }
      }
    }

    deny-disable-cloudtrail = {
      description = "CloudTrail trails and event data stores cannot be stopped, changed or deleted."
      statement = {
        Sid    = "DenyDisableCloudTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteEventDataStore",
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:StopEventDataStoreIngestion",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateEventDataStore",
          "cloudtrail:UpdateTrail",
        ]
        Resource = "*"
      }
    }

    # NotAction inside a Deny: everything except the global services is denied outside
    # the allowed region. The condition narrows it, so the Deny never reaches a call made
    # in the allowed region. The exceptions are explicit prefixes, not a wildcard.
    deny-outside-allowed-region = {
      description = "Requests outside ${var.allowed_region} are denied, except for global services."
      statement = {
        Sid       = "DenyOutsideAllowedRegion"
        Effect    = "Deny"
        NotAction = [for prefix in var.global_service_prefixes : "${prefix}:*"]
        Resource  = "*"
        Condition = {
          StringNotEquals = { "aws:RequestedRegion" = [var.allowed_region] }
        }
      }
    }
  }
}

resource "aws_organizations_policy" "this" {
  for_each = local.policies

  name        = each.key
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  tags        = var.tags

  content = jsonencode({
    Version   = "2012-10-17"
    Statement = [each.value.statement]
  })
}
