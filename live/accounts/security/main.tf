locals {
  # Same key as the backend: CI passes -backend-config=key=<stack>/terraform.tfstate.
  state_key = "live/accounts/security/terraform.tfstate"

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

module "baseline" {
  source = "../../../modules/account-ci-baseline"

  account_name      = "security"
  state_bucket_name = var.state_bucket_name
  state_key         = local.state_key
  tags              = var.tags

  extra_read_statements = local.identity_read_statements
}
