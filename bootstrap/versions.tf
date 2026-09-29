terraform {
  # 1.10 is the first release with the S3 backend's native lockfile (use_lockfile).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: the bucket, key and region come from backend.hcl (gitignored,
  # see backend.hcl.example). CI passes -backend=false to validate.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
