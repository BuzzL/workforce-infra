mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }

  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-1111111111111111"]
      identity_store_ids = ["d-1111111111"]
    }
  }

  mock_data "aws_identitystore_user" {
    defaults = { user_id = "11111111-2222-3333-4444-555555555555" }
  }

  mock_resource "aws_ssoadmin_permission_set" {
    defaults = { arn = "arn:aws:sso:::permissionSet/ssoins-1111111111111111/ps-1111111111111111" }
  }
}

variables {
  region            = "eu-west-1"
  state_bucket_name = "workforce-tfstate-a1b2c3d4"

  maintainer_username    = "maintainer"
  assignment_account_ids = { security = "111122223333", workforce = "444455556666" }
}

run "audit_logging_is_off_by_default" {
  command = plan

  assert {
    condition     = length(module.audit_log_bucket) == 0
    error_message = "Without audit_log_bucket_name the stack must create no log bucket."
  }
}

run "bucket_is_created_for_the_management_trail_when_enabled" {
  command = plan

  variables {
    audit_log_bucket_name = "workforce-audit-logs-example"
    organization_id       = "o-abcdef1234"
    management_account_id = "999988887777"
  }

  assert {
    condition     = length(module.audit_log_bucket) == 1
    error_message = "Setting audit_log_bucket_name must create the log bucket."
  }

  assert {
    condition     = nonsensitive(module.audit_log_bucket[0].bucket_name) == "workforce-audit-logs-example"
    error_message = "The bucket must carry the name that was passed in."
  }
}

run "enabling_without_the_organization_id_is_refused" {
  command = plan

  variables {
    audit_log_bucket_name = "workforce-audit-logs-example"
    management_account_id = "999988887777"
  }

  expect_failures = [var.organization_id]
}

run "enabling_without_the_management_account_is_refused" {
  command = plan

  variables {
    audit_log_bucket_name = "workforce-audit-logs-example"
    organization_id       = "o-abcdef1234"
  }

  expect_failures = [var.management_account_id]
}

run "malformed_management_account_is_refused" {
  command = plan

  variables {
    audit_log_bucket_name = "workforce-audit-logs-example"
    organization_id       = "o-abcdef1234"
    management_account_id = "1234"
  }

  expect_failures = [var.management_account_id]
}

run "an_empty_bucket_name_keeps_it_off" {
  command = plan

  variables {
    audit_log_bucket_name = ""
    organization_id       = ""
    management_account_id = ""
  }

  assert {
    condition     = length(module.audit_log_bucket) == 0
    error_message = "An unset secret arrives as an empty string and must keep the log bucket off."
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
    organization_id       = "o-abcdef1234"
    management_account_id = "999988887777"
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
