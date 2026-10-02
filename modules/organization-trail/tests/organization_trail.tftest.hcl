mock_provider "aws" {}

variables {
  s3_bucket_name = "workforce-audit-logs-example"
}

# Settings are asserted literally on purpose: weakening the trail must be a visible,
# reviewed change to this file.

run "trail_covers_the_organization_with_validated_logs" {
  command = plan

  assert {
    condition = (
      aws_cloudtrail.this.name == "workforce-organization" &&
      aws_cloudtrail.this.is_organization_trail == true &&
      aws_cloudtrail.this.enable_log_file_validation == true &&
      aws_cloudtrail.this.enable_logging == true &&
      aws_cloudtrail.this.include_global_service_events == true
    )
    error_message = "The trail must be an organization trail with log file validation, logging on and global service events."
  }

  assert {
    condition     = aws_cloudtrail.this.is_multi_region_trail == false
    error_message = "One region is in use, so the trail stays single-region."
  }

  assert {
    condition     = aws_cloudtrail.this.s3_bucket_name == "workforce-audit-logs-example"
    error_message = "The trail must write to the given bucket."
  }
}

run "trail_records_management_events_only" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail.this.event_selector) == 0 && length(aws_cloudtrail.this.advanced_event_selector) == 0
    error_message = "No event selectors: the default is management events only, and data events are billed per event."
  }
}
