resource "aws_budgets_budget" "this" {
  name         = var.name
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.limit_usd)
  limit_unit   = "USD"

  dynamic "notification" {
    for_each = toset(var.thresholds_percent)

    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = "ACTUAL"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = var.alert_emails
    }
  }

  lifecycle {
    # AWS fills in UnblendedCost, and the provider only accepts metrics together with a
    # filter expression, so leaving it unset would be a diff on every plan.
    ignore_changes = [metrics]
  }
}
