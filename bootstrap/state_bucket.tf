locals {
  # Commercial partition only: this repo does not target GovCloud or China.
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
}

locals {
  # Role ARNs of the CI roles per member account. security and workforce keep github-infra-<name>
  # under /; the environment accounts follow docs/ENVIRONMENT_PERMISSIONS.md, <key>-foundation-infra-role
  # under /platform/. The path is part of the ARN a bucket policy matches.
  environment_keys = { test = "test", quality = "qual", demo = "demo" }
  member_roles = {
    for name, id in var.member_account_ids : name => {
      apply = contains(keys(local.environment_keys), name) ? "arn:aws:iam::${id}:role/platform/${local.environment_keys[name]}-foundation-infra-role" : "arn:aws:iam::${id}:role/github-infra-${name}"
      plan  = contains(keys(local.environment_keys), name) ? "arn:aws:iam::${id}:role/platform/${local.environment_keys[name]}-foundation-infra-plan-role" : "arn:aws:iam::${id}:role/github-infra-${name}-plan"
      # The state key CI derives from the stack path (scripts/ci-stacks.sh): the account's own stack is
      # live/environments/<name> for an environment and live/accounts/<name> for the others.
      live = contains(keys(local.environment_keys), name) ? "live/environments/${name}" : "live/accounts/${name}"
    }
  }
}

locals {
  # The CI roles of the member accounts (modules/account-ci-baseline) reach the state of their
  # own stack and nothing else in the bucket. Each Allow names one exact role ARN as the
  # principal and one key: no wildcard anywhere. The identity policies of the roles say the
  # same from their side; both are needed for a cross-account request.
  member_state_statements = flatten([
    for name, roles in local.member_roles : [
      {
        Sid       = "List${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = [roles.apply, roles.plan] }
        Action    = "s3:ListBucket"
        Resource  = local.state_bucket_arn
        Condition = { StringEquals = { "s3:prefix" = ["env:/", "${roles.live}/terraform.tfstate", "${roles.live}/terraform.tfstate.tflock", "bootstrap/accounts/${name}/terraform.tfstate", "bootstrap/accounts/${name}/terraform.tfstate.tflock"] } }
      },
      {
        Sid       = "ReadAndWrite${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = roles.apply }
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = "${local.state_bucket_arn}/${roles.live}/terraform.tfstate"
      },
      {
        Sid       = "Lock${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = roles.apply }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource  = "${local.state_bucket_arn}/${roles.live}/terraform.tfstate.tflock"
      },
      {
        Sid       = "Read${title(name)}StateForPlans"
        Effect    = "Allow"
        Principal = { AWS = roles.plan }
        Action    = "s3:GetObject"
        Resource  = "${local.state_bucket_arn}/${roles.live}/terraform.tfstate"
      },
      {
        # The baseline of the account (OIDC provider and the two CI roles) has a stack of its own,
        # applied locally with the maintainer's credentials. Both roles read its state and the
        # apply role takes its lock, so the stack is planned in CI (a drift check). Neither writes
        # the state object: CI cannot change its own role.
        Sid       = "Read${title(name)}BaselineState"
        Effect    = "Allow"
        Principal = { AWS = [roles.apply, roles.plan] }
        Action    = "s3:GetObject"
        Resource  = "${local.state_bucket_arn}/bootstrap/accounts/${name}/terraform.tfstate"
      },
      {
        Sid       = "Lock${title(name)}BaselineState"
        Effect    = "Allow"
        Principal = { AWS = roles.apply }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource  = "${local.state_bucket_arn}/bootstrap/accounts/${name}/terraform.tfstate.tflock"
      },
    ]
  ])
}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3, not a customer-managed KMS key: a key costs money every month, and the state
# holds no secrets.
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  # Versioning is on, so keep history for a while but do not grow forever.
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    # Always keep the newest old versions, so a bad write is recoverable after any delay.
    noncurrent_version_expiration {
      noncurrent_days           = var.noncurrent_version_days
      newer_noncurrent_versions = 10
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "s3:*"
        Resource  = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
      ],
      local.member_state_statements
    )
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}
