mock_provider "aws" {}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"
}

run "wires_the_baseline" {
  command = apply

  assert {
    condition     = local.state_key == "bootstrap/accounts/security/terraform.tfstate"
    error_message = "The state key must match the backend key CI derives from the stack path."
  }

  assert {
    condition     = local.live_state_key == "live/accounts/security/terraform.tfstate"
    error_message = "The apply role must reach the state of live/accounts/security."
  }

  assert {
    condition     = module.baseline.apply_role_arn != module.baseline.plan_role_arn
    error_message = "The apply and plan roles must be different roles."
  }
}

run "bootstrap_account_id_must_be_12_digits" {
  command = plan

  variables {
    break_glass_account_id = "not-an-id"
  }

  expect_failures = [var.break_glass_account_id]
}

run "identity_reads_are_exactly_the_documented_ones" {
  command = apply

  # The whole list, literally: a new action or resource must be a visible change here.
  assert {
    condition = jsonencode(local.identity_read_statements) == jsonencode([
      {
        Sid      = "ReadIdentityCenterInstances"
        Effect   = "Allow"
        Action   = ["sso:ListInstances"]
        Resource = ["*"]
      },
      {
        Sid    = "ReadIdentityCenterPermissionSets"
        Effect = "Allow"
        Action = [
          "sso:DescribePermissionSet",
          "sso:GetInlinePolicyForPermissionSet",
          "sso:GetPermissionsBoundaryForPermissionSet",
          "sso:ListAccountAssignments",
          "sso:ListCustomerManagedPolicyReferencesInPermissionSet",
          "sso:ListManagedPoliciesInPermissionSet",
          "sso:ListPermissionSets",
          "sso:ListTagsForResource",
        ]
        Resource = ["arn:aws:sso:::instance/ssoins-*", "arn:aws:sso:::permissionSet/ssoins-*/ps-*", "arn:aws:sso:::account/*"]
      },
      {
        Sid      = "ReadMaintainerUser"
        Effect   = "Allow"
        Action   = ["identitystore:DescribeUser", "identitystore:GetUserId"]
        Resource = ["*"]
      },
    ])
    error_message = "The identity reads of the CI roles must be exactly the three documented read statements."
  }
}

run "an_empty_bucket_name_keeps_it_off" {
  command = plan

  variables {
    audit_log_bucket_name = ""
  }

  assert {
    condition     = !local.audit_logging
    error_message = "An unset secret arrives as an empty string and must keep audit logging off."
  }

  # The switch is not a secret. CI sends an unset secret as an empty string, which is a sensitive
  # value: without nonsensitive() its sensitivity spreads to the statements and to the CI roles'
  # policies, which then plan an in-place update (a false drift) while logging is off.
  assert {
    condition     = !issensitive(local.audit_logging) && !issensitive(local.audit_read_statements)
    error_message = "The on/off switch and the statements it decides must not be sensitive while logging is off."
  }
}

run "reads_of_the_log_bucket_are_exactly_the_documented_ones" {
  command = plan

  variables {
    audit_log_bucket_name = "workforce-audit-logs-example"
  }

  # The whole list, literally: a new action or resource must be a visible change here.
  assert {
    condition = jsonencode(nonsensitive(local.audit_read_statements)) == jsonencode([
      {
        Sid    = "ReadAuditLogBucket"
        Effect = "Allow"
        Action = [
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketLocation",
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
          "s3:ListBucket",
        ]
        Resource = ["arn:aws:s3:::workforce-audit-logs-example"]
      },
    ])
    error_message = "The CI roles may read the configuration of the log bucket and nothing else: no object reads, no writes, no deletes."
  }
}

run "no_log_bucket_reads_while_it_is_off" {
  command = plan

  assert {
    condition     = length(local.audit_read_statements) == 0
    error_message = "While audit logging is off the CI roles get no log bucket permission."
  }
}

run "identity_center_writes_are_exactly_the_documented_ones" {
  command = apply

  # The whole list, literally: a new action or resource must be a visible change here. No delete,
  # no detach and nothing on IAM: removals are guarded by prevent_destroy, and CI cannot widen
  # its own role.
  assert {
    condition = jsonencode(local.identity_write_statements) == jsonencode([
      {
        Sid    = "ManageIdentityCenterPermissionSets"
        Effect = "Allow"
        Action = [
          "sso:AttachManagedPolicyToPermissionSet",
          "sso:CreatePermissionSet",
          "sso:TagResource",
          "sso:UntagResource",
          "sso:UpdatePermissionSet",
        ]
        Resource = ["arn:aws:sso:::instance/ssoins-*", "arn:aws:sso:::permissionSet/ssoins-*/ps-*"]
      },
      {
        Sid      = "ProvisionAndAssignIdentityCenter"
        Effect   = "Allow"
        Action   = ["sso:CreateAccountAssignment", "sso:ProvisionPermissionSet"]
        Resource = ["arn:aws:sso:::instance/ssoins-*", "arn:aws:sso:::permissionSet/ssoins-*/ps-*", "arn:aws:sso:::account/*"]
      },
      {
        Sid      = "FollowIdentityCenterRequests"
        Effect   = "Allow"
        Action   = ["sso:DescribeAccountAssignmentCreationStatus", "sso:DescribePermissionSetProvisioningStatus"]
        Resource = ["arn:aws:sso:::instance/ssoins-*"]
      },
    ])
    error_message = "The identity writes of the apply role must be exactly the three documented statements."
  }

  assert {
    condition     = alltrue([for s in local.identity_write_statements : alltrue([for a in s.Action : !strcontains(a, "Delete") && !strcontains(a, "Detach") && !startswith(a, "iam:")])])
    error_message = "The apply role must not delete, detach or touch IAM."
  }
}

run "audit_log_bucket_writes_are_exactly_the_documented_ones" {
  command = plan

  variables {
    audit_log_bucket_name = "workforce-audit-logs-example"
  }

  assert {
    condition = jsonencode(nonsensitive(local.audit_write_statements)) == jsonencode([
      {
        Sid    = "ConfigureAuditLogBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
        ]
        Resource = ["arn:aws:s3:::workforce-audit-logs-example"]
      },
    ])
    error_message = "The apply role may create and configure the log bucket and nothing else: no object access, no DeleteBucket."
  }
}

run "no_log_bucket_writes_while_it_is_off" {
  command = plan

  assert {
    condition     = length(local.audit_write_statements) == 0
    error_message = "While audit logging is off the apply role gets no log bucket permission."
  }
}
