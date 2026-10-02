terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: the bucket and region come from backend.hcl; the key is
  # live/guardrails/terraform.tfstate. This stack is applied only locally, with the
  # management SSO admin session (docs/GUARDRAILS_ROLLOUT.md), so the state is read and
  # written with the caller's own credentials.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
