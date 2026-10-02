# Organization trail (docs/AUDIT_LOGGING.md). Off until audit_log_bucket_name is set, which
# happens only after the log bucket exists in the security account: the trail cannot be
# created before its bucket accepts it.
locals {
  # An unset GitHub secret reaches Terraform as an empty string, which must mean off as well.
  audit_logging = try(length(var.audit_log_bucket_name) > 0, false)
}

module "organization_trail" {
  source = "../../modules/organization-trail"
  count  = local.audit_logging ? 1 : 0

  s3_bucket_name = var.audit_log_bucket_name
  tags           = var.tags
}
