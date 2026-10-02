# Organization trail (docs/AUDIT_LOGGING.md). Off until audit_log_bucket_name is set, which
# happens only after the log bucket exists in the security account: the trail cannot be
# created before its bucket accepts it.
locals {
  # An unset GitHub secret reaches Terraform as an empty string, which must mean off as well.
  # Whether logging is on is not a secret, only the bucket name is: without nonsensitive() the
  # sensitivity of the variable would spread to everything this switch decides, including the
  # CI roles' policies, and plan an in-place update of them while logging is off.
  audit_logging = nonsensitive(try(length(var.audit_log_bucket_name) > 0, false))
}

module "organization_trail" {
  source = "../../modules/organization-trail"
  count  = local.audit_logging ? 1 : 0

  s3_bucket_name = var.audit_log_bucket_name
  tags           = var.tags
}
