# The baseline of the security account: the GitHub OIDC provider and the two CI roles
# (modules/account-ci-baseline), with what the roles read and what the apply role writes in the
# stack CI applies, live/accounts/security (Identity Center and the audit log bucket). It is
# applied locally, like bootstrap/, so that the role CI applies with can never change itself
# (docs/ACCOUNT_CI_BASELINES.md).
locals {
  # Same key as the backend: CI passes -backend-config=key=<stack>/terraform.tfstate.
  state_key      = "bootstrap/accounts/security/terraform.tfstate"
  live_state_key = "live/accounts/security/terraform.tfstate"

  # What a plan of this stack reads beyond the baseline: Identity Center and the identity
  # store. Read only. sso:ListInstances and the identity store reads have no resource to
  # scope to; everything else is limited to Identity Center instances, permission sets and
  # accounts, by pattern because their IDs are not known before the call.
  identity_read_statements = [
    {
      Sid      = "ReadIdentityCenterInstances"
      Effect   = "Allow"
      Action   = ["sso:ListInstances"]
      Resource = ["*"]
    },
    {
      Sid    = "ReadIdentityCenterPermissionSets"
      Effect = "Allow"
      Action = [
        "sso:DescribePermissionSet",
        "sso:GetInlinePolicyForPermissionSet",
        "sso:GetPermissionsBoundaryForPermissionSet",
        "sso:ListAccountAssignments",
        "sso:ListCustomerManagedPolicyReferencesInPermissionSet",
        "sso:ListManagedPoliciesInPermissionSet",
        "sso:ListPermissionSets",
        "sso:ListTagsForResource",
      ]
      Resource = ["arn:aws:sso:::instance/ssoins-*", "arn:aws:sso:::permissionSet/ssoins-*/ps-*", "arn:aws:sso:::account/*"]
    },
    {
      Sid      = "ReadMaintainerUser"
      Effect   = "Allow"
      Action   = ["identitystore:DescribeUser", "identitystore:GetUserId"]
      Resource = ["*"]
    },
  ]
}

locals {
  # An unset GitHub secret reaches Terraform as an empty string, which must mean off as well.
  # Whether logging is on is not a secret, only the bucket name is: without nonsensitive() the
  # sensitivity of the variable would spread to everything this switch decides, including the
  # CI roles' policies, and plan an in-place update of them while logging is off.
  audit_logging = nonsensitive(try(length(var.audit_log_bucket_name) > 0, false))
}

locals {
  # What a plan of this stack reads about the log bucket, once it exists. Read only, on
  # exactly the bucket (never its objects): the CI roles cannot read, write or delete a log,
  # and the bucket itself is created and changed locally, not by CI (docs/AUDIT_LOGGING.md).
  audit_read_statements = local.audit_logging ? [
    {
      Sid    = "ReadAuditLogBucket"
      Effect = "Allow"
      Action = [
        "s3:GetAccelerateConfiguration",
        "s3:GetBucketAcl",
        "s3:GetBucketCORS",
        "s3:GetBucketLocation",
        "s3:GetBucketLogging",
        "s3:GetBucketObjectLockConfiguration",
        "s3:GetBucketOwnershipControls",
        "s3:GetBucketPolicy",
        "s3:GetBucketPublicAccessBlock",
        "s3:GetBucketRequestPayment",
        "s3:GetBucketTagging",
        "s3:GetBucketVersioning",
        "s3:GetBucketWebsite",
        "s3:GetEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:GetReplicationConfiguration",
        "s3:ListBucket",
      ]
      Resource = ["arn:aws:s3:::${var.audit_log_bucket_name}"]
    },
  ] : []
}

locals {
  # What live/accounts/security writes, applied by CI after the maintainer's approval on the
  # security environment. The reason is beside each statement. None of it touches IAM and none
  # of it deletes: a plan that would delete any of these resources fails first on
  # prevent_destroy (scripts/check-prevent-destroy.sh), and the log bucket's own policy denies
  # deletion to everyone but the break-glass role. Derived from what the provider calls for
  # each resource and checked against the AWS service reference; a call this list misses shows
  # up as AccessDenied at the first change that needs it, never as a wider grant.
  audit_write_statements = local.audit_logging ? [
    {
      # Create and configure the log bucket (modules/audit-log-bucket: the bucket, its
      # ownership controls, public access block, versioning, encryption, lifecycle and policy).
      # Bucket level only: no object read, write or delete, so CI still cannot touch a log, and
      # no DeleteBucket. CI can rewrite the bucket policy, like any change to this stack, so
      # that change is guarded by review and by the approval of the security environment.
      Sid    = "ConfigureAuditLogBucket"
      Effect = "Allow"
      Action = [
        "s3:CreateBucket",
        "s3:PutBucketOwnershipControls",
        "s3:PutBucketPolicy",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketTagging",
        "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration",
        "s3:PutLifecycleConfiguration",
      ]
      Resource = ["arn:aws:s3:::${var.audit_log_bucket_name}"]
    },
  ] : []

  identity_write_statements = [
    {
      # Create and change the permission sets and attach their managed policy
      # (modules/identity-center-access). Not detach and not delete: those are guarded by
      # prevent_destroy, and removing a set cuts the maintainer's access.
      Sid    = "ManageIdentityCenterPermissionSets"
      Effect = "Allow"
      Action = [
        "sso:AttachManagedPolicyToPermissionSet",
        "sso:CreatePermissionSet",
        "sso:TagResource",
        "sso:UntagResource",
        "sso:UpdatePermissionSet",
      ]
      Resource = ["arn:aws:sso:::instance/ssoins-*", "arn:aws:sso:::permissionSet/ssoins-*/ps-*"]
    },
    {
      # Push a changed set to the accounts that use it, and assign the maintainer to an account.
      # This is the statement group that lets CI change who can reach an account: the control is
      # the maintainer's approval on the security environment, and prevent_destroy on the
      # assignments so that a plan can never remove one. Not DeleteAccountAssignment.
      Sid      = "ProvisionAndAssignIdentityCenter"
      Effect   = "Allow"
      Action   = ["sso:CreateAccountAssignment", "sso:ProvisionPermissionSet"]
      Resource = ["arn:aws:sso:::instance/ssoins-*", "arn:aws:sso:::permissionSet/ssoins-*/ps-*", "arn:aws:sso:::account/*"]
    },
    {
      # Follow the asynchronous requests the two actions above start.
      Sid      = "FollowIdentityCenterRequests"
      Effect   = "Allow"
      Action   = ["sso:DescribeAccountAssignmentCreationStatus", "sso:DescribePermissionSetProvisioningStatus"]
      Resource = ["arn:aws:sso:::instance/ssoins-*"]
    },
  ]
}

module "baseline" {
  source = "../../../modules/account-ci-baseline"

  account_name       = "security"
  state_bucket_name  = var.state_bucket_name
  state_key          = local.live_state_key
  baseline_state_key = local.state_key
  tags               = var.tags

  extra_read_statements  = concat(local.identity_read_statements, local.audit_read_statements)
  extra_write_statements = concat(local.identity_write_statements, local.audit_write_statements)
}
