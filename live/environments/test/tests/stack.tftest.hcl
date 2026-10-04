mock_provider "aws" {}

variables {
  region = "eu-west-1"
}

run "belongs_to_its_environment" {
  command = plan

  assert {
    condition     = output.environment == { name = "test", key = "test" }
    error_message = "The stack must carry the name and key of the test account (scripts/environment-keys.tsv)."
  }

  assert {
    condition     = var.tags.Stack == "live/environments/test" && var.tags.ManagedBy == "terraform"
    error_message = "The default tags must name the stack path."
  }
}
