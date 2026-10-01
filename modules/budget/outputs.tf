output "name" {
  description = "Name of the budget."
  value       = aws_budgets_budget.this.name
}

output "limit_usd" {
  description = "Monthly limit in USD."
  value       = var.limit_usd
}

output "alert_emails" {
  description = "Addresses notified at every threshold."
  value       = var.alert_emails
  sensitive   = true
}
