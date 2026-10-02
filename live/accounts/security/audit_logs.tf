# Log archive of the organization trail (docs/AUDIT_LOGGING.md). Off until audit_log_bucket_name
# is set, so the stack keeps planning clean before the maintainer has set the secrets and the
# CI role may create the bucket.
locals {
  # An unset GitHub secret reaches Terraform as an empty string, which must mean off as well.
  # Whether logging is on is not a secret, only the bucket name is: without nonsensitive() the
  # sensitivity of the variable would spread to everything this switch decides, including the
  # CI roles' policies, and plan an in-place update of them while logging is off.
  audit_logging = nonsensitive(try(length(var.audit_log_bucket_name) > 0, false))
}

module "audit_log_bucket" {
  source = "../../../modules/audit-log-bucket"
  count  = local.audit_logging ? 1 : 0

  bucket_name      = var.audit_log_bucket_name
  organization_id  = var.organization_id
  trail_account_id = var.management_account_id
  trail_region     = var.region
  tags             = var.tags
}

locals {
  # What a plan of this stack reads about the log bucket, once it exists. Read only, on
  # exactly the bucket (never its objects): the CI roles cannot read, write or delete a log,
  # and the bucket itself is created and changed locally, not by CI (docs/AUDIT_LOGGING.md).
  audit_read_statements = local.audit_logging ? [
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
      Resource = ["arn:aws:s3:::${var.audit_log_bucket_name}"]
    },
  ] : []
}
