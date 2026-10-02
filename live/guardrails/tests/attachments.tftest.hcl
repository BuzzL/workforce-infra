mock_provider "aws" {}

# The organization and its units are looked up by data source: fake literal values, so the mock
# needs no real account and the tests assert literal keys and targets.
override_data {
  target = data.aws_organizations_organization.this
  values = {
    roots = [{ id = "r-ab12", arn = "arn:aws:organizations::111122223333:root/o-abcdef1234/r-ab12", name = "Root", policy_types = [] }]
  }
}

override_data {
  target = data.aws_organizations_organizational_units.root
  values = {
    children = [
      { id = "ou-ab12-mgmt0001", arn = "arn:aws:organizations::111122223333:ou/o-abcdef1234/ou-ab12-mgmt0001", name = "Management" },
      { id = "ou-ab12-envs0001", arn = "arn:aws:organizations::111122223333:ou/o-abcdef1234/ou-ab12-envs0001", name = "Environments" },
      { id = "ou-ab12-devl0001", arn = "arn:aws:organizations::111122223333:ou/o-abcdef1234/ou-ab12-devl0001", name = "Development" },
      { id = "ou-ab12-oper0001", arn = "arn:aws:organizations::111122223333:ou/o-abcdef1234/ou-ab12-oper0001", name = "Operations" },
    ]
  }
}

variables {
  region = "eu-south-1"
}

run "nothing_is_attached_by_default" {
  command = apply

  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 0
    error_message = "With no stage set the stack must attach nothing."
  }
}

run "the_four_baseline_policies_exist_without_being_attached" {
  command = apply

  assert {
    condition     = toset(keys(nonsensitive(module.scp_baseline.policy_ids))) == toset(["deny-disable-cloudtrail", "deny-leave-organization", "deny-outside-allowed-region", "deny-root-user"])
    error_message = "The stack must create exactly the four baseline SCPs."
  }
}

run "stage_one_attaches_the_four_policies_to_development_only" {
  command = apply

  variables {
    attachments = {
      Development = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
    }
  }

  assert {
    condition = toset(keys(aws_organizations_policy_attachment.this)) == toset([
      "Development/deny-disable-cloudtrail",
      "Development/deny-leave-organization",
      "Development/deny-outside-allowed-region",
      "Development/deny-root-user",
    ])
    error_message = "Stage one must attach exactly the four policies to Development."
  }

  assert {
    condition     = alltrue([for a in values(aws_organizations_policy_attachment.this) : a.target_id == "ou-ab12-devl0001"])
    error_message = "Every attachment of stage one must target the Development unit."
  }

  assert {
    condition     = alltrue([for key, a in aws_organizations_policy_attachment.this : a.policy_id == nonsensitive(module.scp_baseline.policy_ids)[split("/", key)[1]]])
    error_message = "Each attachment must carry the ID of the policy named in its key."
  }
}

run "every_stage_together_makes_sixteen_attachments_on_four_units" {
  command = apply

  variables {
    attachments = {
      Development  = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
      Environments = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
      Operations   = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
      Management   = ["deny-leave-organization", "deny-root-user", "deny-disable-cloudtrail", "deny-outside-allowed-region"]
    }
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 16
    error_message = "Four policies on four units make sixteen attachments."
  }

  assert {
    condition = toset([for a in values(aws_organizations_policy_attachment.this) : a.target_id]) == toset([
      "ou-ab12-mgmt0001", "ou-ab12-envs0001", "ou-ab12-devl0001", "ou-ab12-oper0001",
    ])
    error_message = "The targets must be exactly the four units."
  }
}

run "no_attachment_targets_the_root_or_an_account" {
  command = apply

  variables {
    attachments = {
      Development  = ["deny-leave-organization"]
      Environments = ["deny-root-user"]
      Management   = ["deny-outside-allowed-region"]
    }
  }

  assert {
    condition = alltrue([
      for a in values(aws_organizations_policy_attachment.this) :
      startswith(a.target_id, "ou-") && a.target_id != "r-ab12" && !can(regex("^[0-9]{12}$", a.target_id))
    ])
    error_message = "A target must be an organizational unit: never the root, never an account."
  }
}

run "the_organization_root_cannot_be_named" {
  command = plan

  variables {
    attachments = { Root = ["deny-root-user"] }
  }

  expect_failures = [var.attachments]
}

run "an_account_cannot_be_named" {
  command = plan

  variables {
    attachments = { "111122223333" = ["deny-root-user"] }
  }

  expect_failures = [var.attachments]
}

run "an_unknown_policy_is_refused" {
  command = plan

  variables {
    attachments = { Development = ["FullAWSAccess"] }
  }

  expect_failures = [var.attachments]
}

run "a_policy_listed_twice_on_a_unit_is_refused" {
  command = plan

  variables {
    attachments = { Development = ["deny-root-user", "deny-root-user"] }
  }

  expect_failures = [var.attachments]
}

run "a_missing_unit_fails_the_plan" {
  command = plan

  override_data {
    target = data.aws_organizations_organizational_units.root
    values = {
      children = [
        { id = "ou-ab12-mgmt0001", arn = "arn:aws:organizations::111122223333:ou/o-abcdef1234/ou-ab12-mgmt0001", name = "Management" },
      ]
    }
  }

  variables {
    attachments = { Development = ["deny-root-user"] }
  }

  expect_failures = [aws_organizations_policy_attachment.this]
}
