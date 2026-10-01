data "aws_caller_identity" "current" {}

locals {
  # Organizations ARNs carry the management account ID and the Organization ID (o-*). The
  # latter is not looked up, so the policies need no Organization-wide read.
  organization_root_arn_pattern = "arn:aws:organizations::${data.aws_caller_identity.current.account_id}:root/o-*/r-*"
  organization_ou_arn_pattern   = "arn:aws:organizations::${data.aws_caller_identity.current.account_id}:ou/o-*/ou-*"

  # What a plan of live/management reads: the OUs of this Organization, nothing about
  # accounts. The root ID comes to the stack as a variable, so no Organization-wide read
  # (which has no resource-level permissions) is needed and no Allow uses Resource "*".
  organization_read_statements = [
    {
      Sid    = "ReadOrganizationalUnits"
      Effect = "Allow"
      Action = [
        "organizations:DescribeOrganizationalUnit",
        "organizations:ListAccountsForParent",
        "organizations:ListOrganizationalUnitsForParent",
        "organizations:ListParents",
        "organizations:ListTagsForResource",
      ]
      Resource = [local.organization_root_arn_pattern, local.organization_ou_arn_pattern]
    }
  ]
}
