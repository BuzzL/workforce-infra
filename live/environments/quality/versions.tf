terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: the bucket and region come from backend.hcl locally and from
  # -backend-config in CI (see .github/workflows/terraform.yml); the key is
  # live/environments/quality/terraform.tfstate.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
