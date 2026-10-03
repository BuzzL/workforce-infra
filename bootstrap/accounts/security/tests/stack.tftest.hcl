mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

# A mock provider cannot import: every adopted resource (imports.tf) is overridden instead.
override_resource {
  target = module.baseline.aws_iam_openid_connect_provider.github
}

override_resource {
  target = module.baseline.aws_iam_role.apply
}

override_resource {
  target = module.baseline.aws_iam_role.plan
}

override_resource {
  target = module.baseline.aws_iam_role_policy.apply_state
}

override_resource {
  target = module.baseline.aws_iam_role_policy.apply_baseline_read
}

override_resource {
  target = module.baseline.aws_iam_role_policy.plan_state_read
}

override_resource {
  target = module.baseline.aws_iam_role_policy.plan_baseline_read
}

override_resource {
  target = module.baseline.aws_iam_role_policies_exclusive.apply
}

override_resource {
  target = module.baseline.aws_iam_role_policies_exclusive.plan
}

override_resource {
  target = module.baseline.aws_iam_role_policy_attachments_exclusive.apply
}

override_resource {
  target = module.baseline.aws_iam_role_policy_attachments_exclusive.plan
}

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
