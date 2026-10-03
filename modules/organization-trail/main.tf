# Organization trail: records every account of the Organization, from the management
# account, into the log bucket of the security account. The Organization must have trusted
# access for cloudtrail.amazonaws.com (docs/AUDIT_LOGGING.md); without it the apply fails.
#
# Single-region on purpose: the region-deny SCP leaves one region in use, so a multi-region
# trail would add nothing but cost. Global service events (IAM, STS) are recorded in the
# home region. Management events only: no data events, which are billed per event.
#
# No customer-managed KMS key: the bucket encrypts the logs with SSE-S3, and a key costs
# money every month and adds a key policy that could lock the logs away. The log file
# validation digest is what proves the logs were not tampered with.
#trivy:ignore:AWS-0015
resource "aws_cloudtrail" "this" {
  name           = var.name
  s3_bucket_name = var.s3_bucket_name
  tags           = var.tags

  is_organization_trail         = true
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true

  # The audit trail itself: a plan that would delete it fails. Turning audit logging off is a
  # reviewed change that deletes this line first.
  lifecycle {
    prevent_destroy = true
  }
}
