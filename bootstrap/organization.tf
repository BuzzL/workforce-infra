data "aws_caller_identity" "current" {}

locals {
  # Organizations ARNs carry the management account ID and the Organization ID (o-*). The
  # latter is not looked up, so the policies need no Organization-wide read.
  organization_root_arn_pattern    = "arn:aws:organizations::${data.aws_caller_identity.current.account_id}:root/o-*/r-*"
  organization_ou_arn_pattern      = "arn:aws:organizations::${data.aws_caller_identity.current.account_id}:ou/o-*/ou-*"
  organization_account_arn_pattern = "arn:aws:organizations::${data.aws_caller_identity.current.account_id}:account/o-*/*"

  # Deleting and updating OUs is allowed on purpose: the stack owns the OUs and must be able
  # to remove one it no longer declares. The OU units are not protected from a bad apply by
  # IAM; the approval of the `management` environment is the guard.
  #
  # What a plan of live/management reads: the OUs and member accounts of this Organization.
  # Accounts are read only: creating one is irreversible and is applied locally with SSO
  # admin (IAT-31), so the CI role has no CreateAccount. The root ID comes to the stack as a variable, so no Organization-wide read
  # (which has no resource-level permissions) is needed and no Allow uses Resource "*".
  organization_read_statements = [
    {
      Sid    = "ReadOrganizationalUnitsAndAccounts"
      Effect = "Allow"
      Action = [
        "organizations:DescribeAccount",
        "organizations:DescribeOrganizationalUnit",
        "organizations:ListAccountsForParent",
        "organizations:ListOrganizationalUnitsForParent",
        "organizations:ListParents",
        "organizations:ListTagsForResource",
      ]
      Resource = [local.organization_root_arn_pattern, local.organization_ou_arn_pattern, local.organization_account_arn_pattern]
    }
  ]
}
