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

  # Deleting a permission set removes the maintainer's access through it. A deliberate removal
  # is a reviewed change that deletes this line first.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = var.permission_sets

  instance_arn       = local.instance_arn
  managed_policy_arn = each.value.managed_policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  # Detaching the policy strips the set of its only permissions.
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

  # Deleting an assignment locks the maintainer out of that account: the lockout this guard
  # exists for. Removing an account from the assigned list is a reviewed change that deletes
  # this line first.
  lifecycle {
    prevent_destroy = true
  }
}
