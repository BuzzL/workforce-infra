locals {
  # Commercial partition only: this repo does not target GovCloud or China.
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
}

locals {
  # The CI roles of the member accounts (modules/account-ci-baseline) reach two state keys and
  # nothing else in the bucket: their account stack (live/accounts/<name>), which the apply role
  # writes, and their roles stack (live/ci-roles/<name>, IAT-82), which holds the roles' own IAM
  # and is applied locally. The apply role only reads and locks the roles key (never writes it),
  # so CI cannot change its own permissions; it reads+locks it so the push drift-plan of that
  # apply=false stack can run, exactly as it does for bootstrap. The plan role reads both keys.
  # Each Allow names one exact role ARN as the principal and one key: no wildcard anywhere. The
  # identity policies of the roles say the same from their side; both are needed cross-account.
  member_state_statements = flatten([
    for name, id in var.member_account_ids : [
      {
        Sid       = "List${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = ["arn:aws:iam::${id}:role/github-infra-${name}", "arn:aws:iam::${id}:role/github-infra-${name}-plan"] }
        Action    = "s3:ListBucket"
        Resource  = local.state_bucket_arn
        Condition = { StringEquals = { "s3:prefix" = ["env:/", "live/accounts/${name}/terraform.tfstate", "live/accounts/${name}/terraform.tfstate.tflock", "live/ci-roles/${name}/terraform.tfstate", "live/ci-roles/${name}/terraform.tfstate.tflock"] } }
      },
      {
        Sid       = "ReadAndWrite${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${id}:role/github-infra-${name}" }
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = "${local.state_bucket_arn}/live/accounts/${name}/terraform.tfstate"
      },
      {
        Sid       = "Lock${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${id}:role/github-infra-${name}" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource  = "${local.state_bucket_arn}/live/accounts/${name}/terraform.tfstate.tflock"
      },
      {
        Sid       = "Read${title(name)}StateForPlans"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${id}:role/github-infra-${name}-plan" }
        Action    = "s3:GetObject"
        Resource  = "${local.state_bucket_arn}/live/accounts/${name}/terraform.tfstate"
      },
      {
        Sid       = "ReadCiRoles${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${id}:role/github-infra-${name}" }
        Action    = "s3:GetObject"
        Resource  = "${local.state_bucket_arn}/live/ci-roles/${name}/terraform.tfstate"
      },
      {
        Sid       = "LockCiRoles${title(name)}State"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${id}:role/github-infra-${name}" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource  = "${local.state_bucket_arn}/live/ci-roles/${name}/terraform.tfstate.tflock"
      },
      {
        Sid       = "ReadCiRoles${title(name)}StateForPlans"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${id}:role/github-infra-${name}-plan" }
        Action    = "s3:GetObject"
        Resource  = "${local.state_bucket_arn}/live/ci-roles/${name}/terraform.tfstate"
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
