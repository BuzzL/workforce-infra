mock_provider "aws" {}

override_resource {
  target = aws_organizations_organizational_unit.this["Management"]
  values = {
    id = "ou-ab12-mgmt0001"
  }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Environments"]
  values = {
    id = "ou-ab12-envs0001"
  }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Development"]
  values = {
    id = "ou-ab12-devl0001"
  }
}

override_resource {
  target = aws_organizations_organizational_unit.this["Operations"]
  values = {
    id = "ou-ab12-ops00001"
  }
}

variables {
  region             = "eu-west-1"
  root_id            = "r-ab12"
  account_email_base = "owner@example.com"
}

# Values are asserted literally on purpose: a new account, a different parent OU or another
# email scheme must be a visible, reviewed change to this file.

run "security_and_workforce_in_their_ous" {
  command = apply

  assert {
    condition     = toset(keys(aws_organizations_account.this)) == toset(["security", "workforce"])
    error_message = "The Organization must have exactly the member accounts security and workforce."
  }

  assert {
    condition = (
      aws_organizations_account.this["security"].parent_id == aws_organizations_organizational_unit.this["Management"].id &&
      aws_organizations_account.this["workforce"].parent_id == aws_organizations_organizational_unit.this["Development"].id
    )
    error_message = "security must sit in the Management OU and workforce in the Development OU."
  }

  assert {
    condition     = alltrue([for name, a in aws_organizations_account.this : a.name == name])
    error_message = "Every account must be named after its key."
  }

  assert {
    condition     = alltrue([for a in aws_organizations_account.this : a.iam_user_access_to_billing == "DENY" && a.close_on_deletion == false])
    error_message = "Accounts must deny IAM billing access and must not be closed on deletion."
  }
}

run "emails_come_from_the_variable" {
  command = apply

  assert {
    condition = (
      aws_organizations_account.this["security"].email == "owner+security@example.com" &&
      aws_organizations_account.this["workforce"].email == "owner+workforce@example.com"
    )
    error_message = "Emails must be local+<account>@domain built from account_email_base."
  }
}

run "account_ids_are_sensitive" {
  command = apply

  assert {
    condition     = issensitive(output.account_ids)
    error_message = "The account_ids output must stay sensitive: the repository is public."
  }

  assert {
    condition     = toset(keys(nonsensitive(output.account_ids))) == toset(["security", "workforce"])
    error_message = "The output must list both accounts by name."
  }
}

# The Organizations API cannot change a member account's email, so a new base must not
# produce a diff on an account that exists (lifecycle ignore_changes).
run "a_new_base_does_not_change_existing_emails" {
  command = apply

  variables {
    account_email_base = "other@example.org"
  }

  assert {
    condition = (
      nonsensitive(aws_organizations_account.this["security"].email) == "owner+security@example.com" &&
      nonsensitive(aws_organizations_account.this["workforce"].email) == "owner+workforce@example.com"
    )
    error_message = "The email of an existing account must be kept when the base changes."
  }
}

run "base_with_plus_is_rejected" {
  command = plan

  variables {
    account_email_base = "owner+x@example.com"
  }

  expect_failures = [var.account_email_base]
}

run "base_making_an_address_over_64_characters_is_rejected" {
  command = plan

  variables {
    account_email_base = "a-very-long-mailbox-name-that-leaves-no-room@a-rather-long-domain.example.com"
  }

  expect_failures = [var.account_email_base]
}

run "base_without_domain_is_rejected" {
  command = plan

  variables {
    account_email_base = "owner"
  }

  expect_failures = [var.account_email_base]
}
