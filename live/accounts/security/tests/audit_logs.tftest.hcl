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
