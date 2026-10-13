# The agent role of docs/ENVIRONMENT_PERMISSIONS.md: read only, identical in every environment,
# so the narrowing rule demo ⊆ quality ⊆ test holds with equality. The permission set is the same
# whatever the key; only the names and ARNs it holds change with the account.
locals {
  prefix = "arn:aws:%s:${var.region}:${var.account_id}:%s"

  # <key>-<project>-<app>-*-<resource>
  names = { for a in var.applications : a => "${var.key}-${var.project}-${a}-*" }

  functions = flatten([for a, n in local.names : [
    format(local.prefix, "lambda", "function:${n}-function"),
    format(local.prefix, "lambda", "function:${n}-function:*"),
  ]])
  stacks = [for a, n in local.names : format(local.prefix, "cloudformation", "stack/${n}-stack/*")]
  log_groups = flatten([for a, n in local.names : [
    format(local.prefix, "logs", "log-group:/aws/lambda/${n}-function"),
    format(local.prefix, "logs", "log-group:/aws/lambda/${n}-function:*"),
  ]])
  log_streams = [for a, n in local.names : format(local.prefix, "logs", "log-group:/aws/lambda/${n}-function:log-stream:*")]
  alarms      = [for a, n in local.names : format(local.prefix, "cloudwatch", "alarm:${n}-alarm")]
}

module "role" {
  source = "../cross-account-role"

  name        = "${var.key}-${var.project}-agent-role"
  description = "Read only access of the developer agent to the ${var.key} account. Assumed from the workforce account."
  tags        = var.tags

  trust = {
    mode = "assume_role"
    assume_role = {
      principal_arn        = var.principal_arn
      extra_principal_arns = var.extra_principal_arns
      source_account_id    = var.workforce_account_id
      external_ids         = var.external_ids
      session_name_pattern = "agent-*"
    }
  }

  statements = [
    {
      sid       = "ReadFunctions"
      actions   = ["lambda:GetFunctionConfiguration", "lambda:GetAlias", "lambda:ListVersionsByFunction", "lambda:ListAliases"]
      resources = local.functions
    },
    {
      sid       = "ReadStacks"
      actions   = ["cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents"]
      resources = local.stacks
    },
    {
      sid       = "ReadLogGroups"
      actions   = ["logs:FilterLogEvents", "logs:DescribeLogStreams"]
      resources = local.log_groups
    },
    {
      sid       = "ReadLogStreams"
      actions   = ["logs:GetLogEvents"]
      resources = local.log_streams
    },
    {
      sid       = "ReadAlarms"
      actions   = ["cloudwatch:DescribeAlarms"]
      resources = local.alarms
    },
  ]
}
