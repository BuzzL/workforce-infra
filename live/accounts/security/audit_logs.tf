# Log archive of the organization trail (docs/AUDIT_LOGGING.md). Off until audit_log_bucket_name
# is set, so the stack keeps planning clean before the maintainer has set the secrets and the
# CI role may create the bucket.
locals {
  # An unset GitHub secret reaches Terraform as an empty string, which must mean off as well.
  audit_logging = try(length(var.audit_log_bucket_name) > 0, false)
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
