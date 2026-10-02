# The CloudTrail service-linked role of the management account. It was created by hand
# (`aws iam create-service-linked-role --aws-service-name cloudtrail.amazonaws.com`) because the
# first CI apply of the organization trail failed without it. The import brings it under
# Terraform without recreating it; once applied, the block is a no-op.
#
# Only tags are managed: the role is AWS-owned (fixed trust and policy), so no description or
# other attribute is set, and the apply role cannot update any (it may tag the role, nothing
# else). prevent_destroy makes a plan that would delete it fail: the audit trail depends on it.
import {
  to = aws_iam_service_linked_role.cloudtrail
  id = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/cloudtrail.amazonaws.com/AWSServiceRoleForCloudTrail"
}

resource "aws_iam_service_linked_role" "cloudtrail" {
  aws_service_name = "cloudtrail.amazonaws.com"

  lifecycle {
    prevent_destroy = true
  }
}
