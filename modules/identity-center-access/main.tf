data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # One assignment per (permission set, account) pair.
  assignments = {
    for pair in flatten([
      for ps, accounts in var.assignments : [for account in accounts : { permission_set = ps, account = account }]
    ]) : "${pair.permission_set}/${pair.account}" => pair
  }
}

data "aws_identitystore_user" "maintainer" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.maintainer_username
    }
  }
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  session_duration = each.value.session_duration
  tags             = var.tags

  # A destroyed set takes its policy attachments and assignments with it: losing it is how the
  # maintainer loses access. Guarded so a CI apply cannot delete it (checked by
  # scripts/check-prevent-destroy.sh); a deliberate removal takes this line out first.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = var.permission_sets

  instance_arn       = local.instance_arn
  managed_policy_arn = each.value.managed_policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  # Detaching the managed policy strips the set of its only permissions (a lockout). Guarded.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_account_assignment" "maintainer" {
  for_each = local.assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn

  principal_id   = data.aws_identitystore_user.maintainer.user_id
  principal_type = "USER"

  target_id   = var.account_ids[each.value.account]
  target_type = "AWS_ACCOUNT"

  # Provisioning an assignment creates the role in the account; keep the order explicit.
  depends_on = [aws_ssoadmin_managed_policy_attachment.this]

  # Deleting an assignment removes the maintainer's access to that account: the lockout class
  # this guard exists for. Guarded so a CI apply cannot delete it.
  lifecycle {
    prevent_destroy = true
  }
}
