# Organization trail (docs/AUDIT_LOGGING.md). Off until audit_log_bucket_name is set, which
# happens only after the log bucket exists in the security account: the trail cannot be
# created before its bucket accepts it.
module "organization_trail" {
  source = "../../modules/organization-trail"
  count  = var.audit_log_bucket_name == null ? 0 : 1

  s3_bucket_name = var.audit_log_bucket_name
  tags           = var.tags
}
