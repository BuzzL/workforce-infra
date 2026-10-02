mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "444455556666" } # fake, and not the trail's account
  }
}

variables {
  bucket_name      = "workforce-audit-logs-example"
  organization_id  = "o-abcdef1234"
  trail_account_id = "111122223333" # fake: the mock must not need a real account
  trail_region     = "eu-south-1"
}

# Values below are asserted literally on purpose: a change to any of them must be a
# visible, reviewed change to this file.

run "bucket_is_private_versioned_and_encrypted" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "All four public access blocks must be on."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Objects must be encrypted at rest."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "The bucket must not be force-destroyable."
  }
}

run "policy_denies_deletion_to_all_but_break_glass_and_admits_only_the_named_trail" {
  command = plan

  assert {
    condition = jsondecode(nonsensitive(aws_s3_bucket_policy.this.policy)) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = { AWS = "*" }
          Action    = "s3:*"
          Resource  = ["arn:aws:s3:::workforce-audit-logs-example", "arn:aws:s3:::workforce-audit-logs-example/*"]
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        },
        {
          Sid       = "DenyLogDeletionExceptBreakGlass"
          Effect    = "Deny"
          Principal = { AWS = "*" }
          Action    = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
          Resource  = "arn:aws:s3:::workforce-audit-logs-example/*"
          Condition = { ArnNotEquals = { "aws:PrincipalArn" = "arn:aws:iam::444455556666:role/OrganizationAccountAccessRole" } }
        },
        {
          Sid       = "DenyBucketDeletionExceptBreakGlass"
          Effect    = "Deny"
          Principal = { AWS = "*" }
          Action    = "s3:DeleteBucket"
          Resource  = "arn:aws:s3:::workforce-audit-logs-example"
          Condition = { ArnNotEquals = { "aws:PrincipalArn" = "arn:aws:iam::444455556666:role/OrganizationAccountAccessRole" } }
        },
        {
          Sid       = "CloudTrailAclCheck"
          Effect    = "Allow"
          Principal = { Service = "cloudtrail.amazonaws.com" }
          Action    = "s3:GetBucketAcl"
          Resource  = "arn:aws:s3:::workforce-audit-logs-example"
          Condition = { StringEquals = { "aws:SourceArn" = "arn:aws:cloudtrail:eu-south-1:111122223333:trail/workforce-organization" } }
        },
        {
          Sid       = "CloudTrailWrite"
          Effect    = "Allow"
          Principal = { Service = "cloudtrail.amazonaws.com" }
          Action    = "s3:PutObject"
          Resource = [
            "arn:aws:s3:::workforce-audit-logs-example/AWSLogs/111122223333/*",
            "arn:aws:s3:::workforce-audit-logs-example/AWSLogs/o-abcdef1234/*",
          ]
          Condition = {
            StringEquals = {
              "aws:SourceArn" = "arn:aws:cloudtrail:eu-south-1:111122223333:trail/workforce-organization"
              "s3:x-amz-acl"  = "bucket-owner-full-control"
            }
          }
        },
      ]
    }
    error_message = "The policy must be the TLS-only Deny, the two deletion Denies (everyone but the break-glass role) and two Allows for the one trail ARN, and nothing else."
  }
}

run "lifecycle_expires_logs_and_old_versions" {
  command = plan

  assert {
    condition = (
      one(aws_s3_bucket_lifecycle_configuration.this.rule).status == "Enabled" &&
      one(one(aws_s3_bucket_lifecycle_configuration.this.rule).expiration).days == 365 &&
      one(one(aws_s3_bucket_lifecycle_configuration.this.rule).noncurrent_version_expiration).noncurrent_days == 90
    )
    error_message = "Logs must expire after 365 days and noncurrent versions after 90 by default."
  }
}

run "retention_below_ninety_days_is_refused" {
  command = plan

  variables {
    log_retention_days = 30
  }

  expect_failures = [var.log_retention_days]
}

run "malformed_organization_id_is_refused" {
  command = plan

  variables {
    organization_id = "r-abcd"
  }

  expect_failures = [var.organization_id]
}

run "empty_bucket_name_is_refused" {
  command = plan

  variables {
    bucket_name = ""
  }

  expect_failures = [var.bucket_name]
}

run "noncurrent_retention_below_one_day_is_refused" {
  command = plan

  variables {
    noncurrent_version_days = 0
  }

  expect_failures = [var.noncurrent_version_days]
}
