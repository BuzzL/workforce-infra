mock_provider "aws" {}

variables {
  region  = "eu-west-1"
  root_id = "r-ab12"
}

# Values are asserted literally on purpose: a change to the OU names or their parent must
# be a visible, reviewed change to this file.

run "four_top_level_units_under_the_root" {
  command = apply

  assert {
    condition     = toset(keys(aws_organizations_organizational_unit.this)) == toset(["Management", "Environments", "Development", "Operations"])
    error_message = "The Organization must have exactly the OUs Management, Environments, Development and Operations."
  }

  assert {
    condition     = alltrue([for name, ou in aws_organizations_organizational_unit.this : ou.name == name && ou.parent_id == "r-ab12"])
    error_message = "Every OU must be named after its key and sit directly under the Organization root."
  }

  assert {
    condition     = toset(keys(output.organizational_unit_ids)) == toset(["Management", "Environments", "Development", "Operations"])
    error_message = "The output must list the four OUs by name."
  }
}

run "root_id_must_look_like_a_root_id" {
  command = plan

  variables {
    root_id = "ou-ab12-cdef5678"
  }

  expect_failures = [var.root_id]
}
