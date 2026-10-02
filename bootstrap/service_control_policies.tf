# What CI needs to manage service control policies in live/management: create, change, attach to
# organizational units and detach the SCPs the stack owns. The roles can not touch anything else:
# attaching and detaching are limited to SCPs of this Organization and to organizational units, so
# they can neither attach to the root or to an account, nor detach FullAWSAccess (an AWS-managed
# policy, whose ARN is outside the pattern). The guard on a harmful stage is the review of the
# PR and the approval of the `management` environment, not IAM.
locals {
  scp_arn_pattern             = "arn:aws:organizations::${data.aws_caller_identity.current.account_id}:policy/o-*/service_control_policy/p-*"
  scp_aws_managed_arn_pattern = "arn:aws:organizations::aws:policy/service_control_policy/p-*"

  # Reads of SCPs: a policy, its tags, and what it is attached to. The AWS-managed ones are only
  # read (the stack looks the hand-made policy up among all of them by name). ListPolicies has no
  # resource-level permission.
  scp_read_statements = [
    {
      Sid      = "ReadServiceControlPolicies"
      Effect   = "Allow"
      Action   = ["organizations:DescribePolicy", "organizations:ListTagsForResource", "organizations:ListTargetsForPolicy"]
      Resource = [local.scp_arn_pattern, local.scp_aws_managed_arn_pattern]
    },
    {
      Sid      = "ListServiceControlPolicies"
      Effect   = "Allow"
      Action   = ["organizations:ListPolicies"]
      Resource = ["*"]
    },
  ]
}

resource "aws_iam_role_policy" "service_control_policies" {
  name = "service-control-policies"
  role = aws_iam_role.github_infra_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.scp_read_statements, [
      # A new policy's ARN is not known before the call and CreatePolicy has no resource-level
      # permission. A policy attached nowhere does nothing.
      {
        Sid      = "CreateServiceControlPolicies"
        Effect   = "Allow"
        Action   = ["organizations:CreatePolicy"]
        Resource = ["*"]
      },
      # The stack owns its SCPs, so it may change and delete them, as it may the OUs. The imported
      # hand-made one has prevent_destroy in the code.
      {
        Sid      = "ManageServiceControlPolicies"
        Effect   = "Allow"
        Action   = ["organizations:UpdatePolicy", "organizations:DeletePolicy", "organizations:TagResource", "organizations:UntagResource"]
        Resource = [local.scp_arn_pattern]
      },
      # AttachPolicy and DetachPolicy are evaluated on the policy and on the target. The target
      # list holds organizational units only: no root, no account.
      {
        Sid      = "AttachServiceControlPoliciesToUnits"
        Effect   = "Allow"
        Action   = ["organizations:AttachPolicy", "organizations:DetachPolicy"]
        Resource = [local.scp_arn_pattern, local.organization_ou_arn_pattern]
      },
    ])
  })
}

resource "aws_iam_role_policy" "plan_service_control_policies" {
  name = "plan-service-control-policies"
  role = aws_iam_role.github_infra_management_plan.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.scp_read_statements
  })
}
