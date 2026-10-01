data "aws_caller_identity" "current" {}

# The budget was created by hand before this stack existed. The import block brings it under
# Terraform without recreating it; once applied, the block is a no-op and can stay or go.
import {
  to = module.budget.aws_budgets_budget.this
  id = "${data.aws_caller_identity.current.account_id}:${var.budget_name}"
}

module "budget" {
  source = "../../modules/budget"

  name         = var.budget_name
  limit_usd    = var.budget_limit_usd
  alert_emails = [var.budget_alert_email]
}
